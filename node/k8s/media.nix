{ config, ... }:
let
  namespace = "media";
  transmission-peer-port = 31413;
  transmission-rpc-port = 9091;
  transmission-download-dir = "/media/downloads/completed";
  transmission-incomplete-dir = "/media/downloads/inprogress";
  transmission-watch-dir = "/media/downloads/watch";
in
{
  services.k3s.manifests = {
    media-namespace.content = {
      apiVersion = "v1";
      kind = "Namespace";
      metadata = {
        name = namespace;
      };
    };
    media-storage.content = {
      apiVersion = "v1";
      kind = "PersistentVolumeClaim";
      metadata = {
        name = "media";
        namespace = namespace;
      };
      spec = {
        storageClassName = "storage";
        resources.requests.storage = "2Ti";
        accessModes = [ "ReadWriteMany" ];
        persistentVolumeReclaimPolicy = "Retain";
      };
    };
    transmission-config.content = {
      apiVersion = "v1";
      kind = "ConfigMap";
      metadata = {
        name = "transmission-config";
        namespace = namespace;
      };
      data."settings.json" = builtins.toJSON {
        download-dir = transmission-download-dir;
        incomplete-dir = transmission-incomplete-dir;
        watch-dir = transmission-watch-dir;
        watch-dir-enabled = true;
        incomplete-dir-enabled = true;
        trash-can-enabled = false;
        trash-original-torrent-files = false;
        peer-port = transmission-peer-port;
        port-forwarding-enabled = false;
        rpc-enabled = true;
        rpc-port = transmission-rpc-port;
        rpc-password = "";
        rpc-whitelist-enabled = false;
        speed-limit-down = 5000;
        speed-limit-down-enabled = true;
        dht-enabled = true;
        lpd-enabled = true;
        preferred-transports = [ "tcp" ];
        tcp-enabled = true;
        utp-enabled = false;
      };
    };
    transmission-statefulset-service.content = {
      apiVersion = "v1";
      kind = "Service";
      metadata = {
        name = "transmission-headless";
        namespace = namespace;
      };
      spec = {
        selector.app = "transmission";
        type = "ClusterIP";
        clusterIP = "None";
        ports = [
          {
            name = "rpc";
            port = transmission-rpc-port;
            protocol = "TCP";
            targetPort = "rpc";
          }
        ];
      };
    };
    transmission-statefulset.content = {
      apiVersion = "apps/v1";
      kind = "StatefulSet";
      metadata = {
        name = "transmission";
        namespace = namespace;
        annotations."reloader.stakater.com/auto" = "true";
      };
      spec = {
        selector.matchLabels.app = "transmission";
        serviceName = "transmission-headless";
        volumeClaimTemplates = [
          {
            apiVersion = "v1";
            kind = "PersistentVolumeClaim";
            metadata.name = "transmission-state";
            spec = {
              accessModes = [ "ReadWriteOnce" ];
              resources.requests.storage = "1Gi";
            };
          }
        ];
        template = {
          metadata.labels.app = "transmission";
          spec = {
            volumes = [
              {
                name = "config-ro";
                configMap.name = "transmission-config";
              }
              {
                name = "media";
                persistentVolumeClaim.claimName = "media";
              }
            ];
            initContainers = [
              {
                name = "mkdir";
                image = "rancher/mirrored-library-busybox:1.36.1";
                command = [
                  "sh"
                  "-c"
                ];
                args = [
                  "set -eux && mkdir -p -m 0777 ${transmission-download-dir} ${transmission-incomplete-dir} ${transmission-watch-dir} && cp /config-ro/settings.json /config/settings.json && chmod 0666 /config/settings.json"
                ];
                volumeMounts = [
                  {
                    name = "config-ro";
                    mountPath = "/config-ro";
                  }
                  {
                    name = "transmission-state";
                    mountPath = "/config";
                  }
                  {
                    name = "media";
                    mountPath = "/media";
                  }
                ];
                resources = {
                  requests = {
                    cpu = "100m";
                    memory = "128Mi";
                  };
                  limits = {
                    cpu = "500m";
                    memory = "512Mi";
                  };
                };
              }
            ];
            containers = [
              {
                name = "transmission";
                image = "linuxserver/transmission:4.0.6";
                volumeMounts = [
                  {
                    name = "transmission-state";
                    mountPath = "/config";
                  }
                  {
                    name = "media";
                    mountPath = "/media";
                  }
                ];
                ports = [
                  {
                    name = "rpc";
                    protocol = "TCP";
                    containerPort = transmission-rpc-port;
                  }
                  {
                    name = "peer-tcp";
                    protocol = "TCP";
                    containerPort = transmission-peer-port;
                  }
                  {
                    name = "peer-udp";
                    protocol = "UDP";
                    containerPort = transmission-peer-port;
                  }
                ];
                resources = {
                  requests = {
                    cpu = "100m";
                    memory = "128Mi";
                  };
                  limits = {
                    cpu = "500m";
                    memory = "512Mi";
                  };
                };
              }
            ];
          };
        };
      };
    };
    transmission-rpc-service.content = {
      apiVersion = "v1";
      kind = "Service";
      metadata = {
        name = "transmission-rpc";
        namespace = namespace;
      };
      spec = {
        selector.app = "transmission";
        type = "ClusterIP";
        ports = [
          {
            name = "rpc";
            port = transmission-rpc-port;
            protocol = "TCP";
            targetPort = "rpc";
          }
        ];
      };
    };
    transmission-peer-service.content = {
      apiVersion = "v1";
      kind = "Service";
      metadata = {
        name = "transmission-peer";
        namespace = namespace;
      };
      spec = {
        selector.app = "transmission";
        type = "NodePort";
        ports = [
          {
            name = "peer-tcp";
            port = transmission-peer-port;
            nodePort = transmission-peer-port;
            protocol = "TCP";
            targetPort = "peer-tcp";
          }
          {
            name = "peer-udp";
            port = transmission-peer-port;
            nodePort = transmission-peer-port;
            protocol = "UDP";
            targetPort = "peer-udp";
          }
        ];
      };
    };
    transmission-rpc-httproute.content = {
      apiVersion = "gateway.networking.k8s.io/v1";
      kind = "HTTPRoute";
      metadata = {
        name = "transmission-rpc";
        namespace = namespace;
      };
      spec = {
        hostnames = [ "transmission.home.iverian.ru" ];
        parentRefs = [
          {
            group = "gateway.networking.k8s.io";
            kind = "Gateway";
            name = "main";
            namespace = "envoy-gateway-system";
          }
        ];
        rules = [
          {
            backendRefs = [
              {
                group = "";
                kind = "Service";
                name = "transmission-rpc";
                port = transmission-rpc-port;
              }
            ];
            matches = [
              {
                path = {
                  type = "PathPrefix";
                  value = "/";
                };
              }
            ];
          }
        ];
      };
    };
    transmission-remove-added-files.content = {
      apiVersion = "batch/v1";
      kind = "CronJob";
      metadata = {
        name = "transmission-remove-added-files";
        namespace = namespace;
      };
      spec = {
        schedule = "0 4 * * *";
        jobTemplate.spec.template.spec = {
          restartPolicy = "OnFailure";
          volumes = [
            {
              name = "media";
              persistentVolumeClaim.claimName = "media";
            }
          ];
          containers = [
            {
              name = "main";
              image = "rancher/mirrored-library-busybox:1.36.1";
              command = [
                "sh"
                "-c"
              ];
              args = [ "set -eux && rm -f ${transmission-watch-dir}/*.added" ];
              volumeMounts = [
                {
                  name = "media";
                  mountPath = "/media";
                }
              ];
            }
          ];
        };
      };
    };
    jellyfin-config.content = {
      apiVersion = "v1";
      kind = "ConfigMap";
      metadata = {
        name = "jellyfin-config";
        namespace = namespace;
      };
      data."settings.json" = "";
    };
    jellyfin-statefulset-service.content = {
      apiVersion = "v1";
      kind = "Service";
      metadata = {
        name = "jellyfin-headless";
        namespace = namespace;
      };
      spec = {
        selector.app = "jellyfin";
        type = "ClusterIP";
        clusterIP = "None";
        ports = [
          {
            name = "rpc";
            port = 8096;
            protocol = "TCP";
            targetPort = "rpc";
          }
        ];
      };
    };
    jellyfin-statefulset.content = {
      apiVersion = "apps/v1";
      kind = "StatefulSet";
      metadata = {
        name = "jellyfin";
        namespace = namespace;
        annotations."reloader.stakater.com/auto" = "true";
      };
      spec = {
        selector.matchLabels.app = "jellyfin";
        serviceName = "jellyfin-headless";
        volumeClaimTemplates = [
          {
            apiVersion = "v1";
            kind = "PersistentVolumeClaim";
            metadata.name = "jellyfin-state";
            spec = {
              accessModes = [ "ReadWriteOnce" ];
              resources.requests.storage = "1Gi";
            };
          }
        ];
        template = {
          metadata.labels.app = "jellyfin";
          spec = {
            volumes = [
              {
                name = "media";
                persistentVolumeClaim.claimName = "media";
              }
            ];
            containers = [
              {
                name = "jellyfin";
                image = "ghcr.io/jellyfin/jellyfin:latest";
                env = [
                  {
                    name = "JELLYFIN_PublishedServerUrl";
                    value = "https://jellyfin.home.iverian.ru";
                  }
                  {
                    name = "JELLYFIN_DATA_DIR";
                    value = "/config";
                  }
                ];
                volumeMounts = [
                  {
                    name = "jellyfin-state";
                    mountPath = "/state";
                  }
                  {
                    name = "media";
                    mountPath = "/media";
                  }
                ];
                ports = [
                  {
                    name = "http";
                    protocol = "TCP";
                    containerPort = 8096;
                  }
                  {
                    name = "discovery";
                    protocol = "UDP";
                    containerPort = 7359;
                  }
                ];
                resources = {
                  requests = {
                    cpu = "100m";
                    memory = "128Mi";
                  };
                  limits = {
                    cpu = "1";
                    memory = "2Gi";
                  };
                };
              }
            ];
          };
        };
      };
    };
    jellyfin-service.content = {
      apiVersion = "v1";
      kind = "Service";
      metadata = {
        name = "jellyfin";
        namespace = namespace;
      };
      spec = {
        selector.app = "jellyfin";
        type = "ClusterIP";
        ports = [
          {
            name = "http";
            port = 80;
            protocol = "TCP";
            targetPort = "http";
          }
        ];
      };
    };
    jellyfin-discovery-service.content = {
      apiVersion = "v1";
      kind = "Service";
      metadata = {
        name = "jellyfin";
        namespace = namespace;
      };
      spec = {
        selector.app = "jellyfin";
        type = "NodePort";
        ports = [
          {
            name = "discovery";
            port = 7359;
            protocol = "UDP";
            targetPort = "discovery";
          }
        ];
      };
    };
    jellyfin-httproute.content = {
      apiVersion = "gateway.networking.k8s.io/v1";
      kind = "HTTPRoute";
      metadata = {
        name = "jellyfin";
        namespace = namespace;
      };
      spec = {
        hostnames = [ "jellyfin.home.iverian.ru" ];
        parentRefs = [
          {
            group = "gateway.networking.k8s.io";
            kind = "Gateway";
            name = "main";
            namespace = "envoy-gateway-system";
          }
        ];
        rules = [
          {
            backendRefs = [
              {
                group = "";
                kind = "Service";
                name = "jellyfin";
                port = 80;
              }
            ];
            matches = [
              {
                path = {
                  type = "PathPrefix";
                  value = "/";
                };
              }
            ];
          }
        ];
      };
    };
    share-security-config.content = {
      apiVersion = "samba-operator.samba.org/v1alpha1";
      kind = "SmbSecurityConfig";
      metadata = {
        name = "external";
        namespace = namespace;
      };
      spec = {
        mode = "user";
        dns.register = "never";
        users = {
          secret = "share-users";
          key = "users";
        };
      };
    };
    share-common-config.content = {
      apiVersion = "samba-operator.samba.org/v1alpha1";
      kind = "SmbCommonConfig";
      metadata = {
        name = "external";
        namespace = namespace;
      };
      spec.network.publish = "external";
    };
    media-share.content = {
      apiVersion = "samba-operator.samba.org/v1alpha1";
      kind = "SmbShare";
      metadata = {
        name = "share";
        namespace = namespace;
      };
      spec = {
        storage.pvc = {
          name = "media";
        };
        securityConfig = "external";
        commonConfig = "external";
        shareName = "media";
        browseable = true;
        readOnly = false;
      };
    };

  };
  sops = {
    secrets = {
      shareUsers = { };
    };
    templates.media-share-users = {
      content = builtins.toJSON {
        apiVersion = "v1";
        kind = "Secret";
        metadata = {
          name = "share-users";
          namespace = namespace;
        };
        data = {
          users = config.sops.placeholder.shareUsers;
        };
      };
      path = "/var/lib/rancher/k3s/server/manifests/media-share-users.json";
    };
  };
}
