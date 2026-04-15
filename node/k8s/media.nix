{ config, ... }:
let
  namespace = "media";
  transmission-peer-port = 31413;
  transmission-rpc-port = 9091;
  vidsort-http-port = 8080;
  transmission-download-dir = "/media/downloads/completed";
  transmission-incomplete-dir = "/media/downloads/inprogress";
  transmission-watch-dir = "/media/downloads/watch";
  movies-dir = "/media/movies";
  shows-dir = "/media/shows";
  other-dir = "/media/other";
  transcode-dir = "/media/.transcode";
  vidsort-dir = "/config/vidsort";
in
{
  sops = {
    secrets = {
      tvdbApiKey = { };
    };
    templates = {
      vidsort-secret = {
        content = builtins.toJSON {
          apiVersion = "v1";
          kind = "Secret";
          metadata = {
            name = "vidsort-secret";
            namespace = namespace;
          };
          stringData = {
            VIDSORT_TVDB_API_KEY = config.sops.placeholder.tvdbApiKey;
          };
        };
        path = "/var/lib/rancher/k3s/server/manifests/media-vidsort-secret.json";
      };
    };
  };

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
      data = {
        "settings.json" = builtins.toJSON {
          download-dir = transmission-download-dir;
          incomplete-dir = transmission-incomplete-dir;
          watch-dir = transmission-watch-dir;
          watch-dir-enabled = true;
          incomplete-dir-enabled = true;
          umask = "000";
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
          speed-limit-up = 5000;
          speed-limit-up-enabled = true;
          dht-enabled = true;
          lpd-enabled = true;
          preferred-transports = [ "tcp" ];
          tcp-enabled = true;
          utp-enabled = false;
          script-torrent-done-enabled = true;
          script-torrent-added-filename = "/config/on-done.sh";
        };
        "on-done.sh" = ''
          #!/bin/sh

          FIFO_PATH="/config/vidsort/fifo"

          if [ -e "$FIFO_PATH" ] ; then
            echo "''\${TR_TORRENT_ID}" >> "$FIFO_PATH"
          fi
        '';
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
          metadata = {
            labels.app = "transmission";
            annotations."reloader.stakater.com/auto" = "true";
          };
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
                  "set -eux && mkdir -p ${movies-dir} ${shows-dir} ${other-dir} ${transcode-dir} ${transmission-download-dir} ${transmission-incomplete-dir} ${transmission-watch-dir} ${vidsort-dir} && chmod -R 0777 ${movies-dir} ${shows-dir} ${other-dir} ${transcode-dir} ${transmission-download-dir} ${transmission-incomplete-dir} ${transmission-download-dir} ${vidsort-dir} && cp /config-ro/settings.json /config-ro/on-done.sh /config/ && chmod -R 0777 /config"
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
                name = "vidsort";
                image = "gitea.home.iverian.ru/iverian/vidsort:0.1.2";
                imagePullPolicy = "Always";
                envFrom = [
                  {
                    secretRef.name = "vidsort-secret";
                  }
                ];
                env = [
                  {
                    name = "VIDSORT_BIND";
                    value = "0.0.0.0:8080";
                  }
                  {
                    name = "VIDSORT_LOG_FORMAT";
                    value = "json";
                  }
                  {
                    name = "VIDSORT_LOG";
                    value = "info";
                  }
                  {
                    name = "VIDSORT_FIFO_PATH";
                    value = "/config/vidsort/fifo";
                  }
                  {
                    name = "VIDSORT_TVDB_CACHE_PATH";
                    value = "/config/vidsort/cache";
                  }
                  {
                    name = "VIDSORT_TRANSMISSION_URL";
                    value = "http://transmission-rpc:${toString (transmission-rpc-port)}/transmission/rpc";
                  }
                  {
                    name = "VIDSORT_IMDB_BLACKLIST";
                    value = "tt0892051";
                  }
                  {
                    name = "VIDSORT_MOVIES_DIR";
                    value = movies-dir;
                  }
                  {
                    name = "VIDSORT_SHOWS_DIR";
                    value = shows-dir;
                  }
                  {
                    name = "VIDSORT_OTHER_DIR";
                    value = other-dir;
                  }
                ];
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
                    name = "vidsort-http";
                    protocol = "TCP";
                    containerPort = vidsort-http-port;
                  }
                ];
                resources = {
                  requests = {
                    cpu = "50m";
                    memory = "128Mi";
                  };
                  limits = {
                    cpu = "100m";
                    memory = "256Mi";
                  };
                };
              }
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
    vidsort-rpc-service.content = {
      apiVersion = "v1";
      kind = "Service";
      metadata = {
        name = "vidsort";
        namespace = namespace;
      };
      spec = {
        selector.app = "transmission";
        type = "ClusterIP";
        ports = [
          {
            name = "vidsort-http";
            port = vidsort-http-port;
            protocol = "TCP";
            targetPort = "vidsort-http";
          }
        ];
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
                  {
                    name = "JELLYFIN_CONFIG_DIR";
                    value = "/config/config";
                  }
                  {
                    name = "JELLYFIN_CACHE_DIR";
                    value = "/config/cache";
                  }
                  {
                    name = "JELLYFIN_LOG_DIR";
                    value = "/config/log";
                  }
                  {
                    name = "NODE_NAME";
                    valueFrom.fieldRef = {
                      apiVersion = "v1";
                      fieldPath = "spec.nodeName";
                    };
                  }
                  {
                    name = "POD_NAME";
                    valueFrom.fieldRef = {
                      apiVersion = "v1";
                      fieldPath = "metadata.name";
                    };
                  }
                  {
                    name = "POD_NAMESPACE";
                    valueFrom.fieldRef = {
                      apiVersion = "v1";
                      fieldPath = "metadata.namespace";
                    };
                  }
                ];
                volumeMounts = [
                  {
                    name = "jellyfin-state";
                    mountPath = "/config";
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
                ];
                resources = {
                  requests = {
                    cpu = "100m";
                    memory = "128Mi";
                    "gpu.intel.com/i915" = "1";
                  };
                  limits = {
                    cpu = "1";
                    memory = "2Gi";
                    "gpu.intel.com/i915" = "1";
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
    jellyfin-tailscale-ingress.content = {
      apiVersion = "networking.k8s.io/v1";
      kind = "Ingress";
      metadata = {
        name = "ts-jellyfin";
        namespace = namespace;
      };
      spec = {
        defaultBackend.service = {
          name = "jellyfin";
          port.number = 80;
        };
        ingressClassName = "tailscale";
        tls = [ { hosts = [ "jellyfin" ]; } ];
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
    media-share-service-tailscale.content = {
      apiVersion = "v1";
      kind = "Service";
      metadata = {
        name = "share-ext";
        namespace = namespace;
      };
      spec = {
        selector."samba-operator.samba.org/service" = "share";
        type = "LoadBalancer";
        loadBalancerClass = "tailscale";
        ports = [
          {
            name = "smb";
            port = 445;
            protocol = "TCP";
            targetPort = 445;
          }
        ];
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
