{ config, ... }:
let
  namespace = "backup";
  rclone-config = "rclone-config";
in
{
  sops = {
    secrets = {
      rcloneConfigB64 = { };
    };
    templates = {
      rclone-config = {
        content = builtins.toJSON {
          apiVersion = "v1";
          kind = "Secret";
          metadata = {
            name = rclone-config;
            namespace = namespace;
          };
          data = {
            "rclone.conf" = config.sops.placeholder.rcloneConfigB64;
          };
        };
        path = "/var/lib/rancher/k3s/server/manifests/rclone-config.json";
      };
    };
  };

  services.k3s.manifests = {
    backup-namespace.content = {
      apiVersion = "v1";
      kind = "Namespace";
      metadata.name = namespace;
    };
    backup-rclone-statefulset-service.content = {
      apiVersion = "v1";
      kind = "Service";
      metadata = {
        name = "rclone-serve-headless";
        namespace = namespace;
      };
      spec = {
        selector.app = "rclone-serve";
        type = "ClusterIP";
        clusterIP = "None";
        ports = [
          {
            name = "s3";
            port = 80;
            protocol = "TCP";
            targetPort = "s3";
          }
        ];
      };
    };
    backup-rclone-service.content = {
      apiVersion = "v1";
      kind = "Service";
      metadata = {
        name = "rclone-serve";
        namespace = namespace;
      };
      spec = {
        selector.app = "rclone-serve";
        type = "ClusterIP";
        ports = [
          {
            name = "s3";
            port = 80;
            protocol = "TCP";
            targetPort = "s3";
          }
        ];
      };
    };
    backup-rclone-statefulset.content = {
      apiVersion = "apps/v1";
      kind = "StatefulSet";
      metadata = {
        name = "rclone-serve";
        namespace = namespace;
      };
      spec = {
        selector.matchLabels.app = "rclone-serve";
        serviceName = "rclone-serve-headless";
        volumeClaimTemplates = [
          {
            apiVersion = "v1";
            kind = "PersistentVolumeClaim";
            metadata.name = "rclone-serve-state";
            spec = {
              accessModes = [ "ReadWriteOnce" ];
              resources.requests.storage = "1Gi";
            };
          }
        ];
        template = {
          metadata = {
            labels.app = "rclone-serve";
            annotations."reloader.stakater.com/auto" = "true";
          };
          spec = {
            volumes = [
              {
                name = "config-ro";
                secret.secretName = rclone-config;
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
                  "set -eux && mkdir -p /state/cache && cp /config-ro/rclone.conf /state/rclone.conf"
                ];
                volumeMounts = [
                  {
                    name = "config-ro";
                    mountPath = "/config-ro";
                  }
                  {
                    name = "rclone-serve-state";
                    mountPath = "/state";
                  }
                ];
                resources = {
                  requests = {
                    cpu = "50m";
                    memory = "128Mi";
                  };
                  limits = {
                    cpu = "100m";
                    memory = "512Mi";
                  };
                };
              }
            ];
            containers = [
              {
                name = "rclone";
                image = "rclone/rclone:sha-0157a1f";
                args = [
                  "serve"
                  "s3"
                  "crypt:"
                  "--config"
                  "/state/rclone.conf"
                  "--addr"
                  "0.0.0.0:8080"
                  "--cache-dir"
                  "/state/cache"
                  "--vfs-cache-mode"
                  "off"
                ];
                env = [
                  {
                    name = "RCLONE_AUTH_KEY";
                    value = "\"user,pass\"";
                  }
                ];
                volumeMounts = [
                  {
                    name = "rclone-serve-state";
                    mountPath = "/state";
                  }
                ];
                ports = [
                  {
                    name = "s3";
                    protocol = "TCP";
                    containerPort = 8080;
                  }
                ];
                resources = {
                  requests = {
                    cpu = "50m";
                    memory = "128Mi";
                  };
                  limits = {
                    cpu = "100m";
                    memory = "512Mi";
                  };
                };
              }
            ];
          };
        };
      };
    };
  };
}
