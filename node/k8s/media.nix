{ config, ... }:
let
  namespace = "media";
  transmission-peer-port = 32413;
  transmission-rpc-port = 9091;
  transmission-download-dir = "/media/downloads/complete";
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
        trash-original-torrent-files = true;
        peer-port = transmission-peer-port;
        port-forwarding-enabled = false;
        rpc-enabled = true;
        rpc-port = transmission-rpc-port;
        rpc-password = "";
        rpc-whitelist-enabled = false;
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
  };
}
