{ ... }:
let
  namespace = "backup";
in
{
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
            metadata.name = "rclone-serve-staging";
            spec = {
              accessModes = [ "ReadWriteOnce" ];
              storageClassName = "storage";
              resources.requests.storage = "20Gi";
            };
          }
        ];
        template = {
          metadata = {
            labels.app = "rclone-serve";
            annotations."reloader.stakater.com/auto" = "true";
          };
          spec = {
            initContainers = [
              {
                name = "prepare-staging";
                image = "rancher/mirrored-library-busybox:1.36.1";
                command = [
                  "sh"
                  "-c"
                ];
                args = [ "mkdir -p /data/postgres" ];
                volumeMounts = [
                  {
                    name = "rclone-serve-staging";
                    mountPath = "/data";
                  }
                ];
                resources = {
                  requests = {
                    cpu = "10m";
                    memory = "16Mi";
                  };
                  limits = {
                    cpu = "50m";
                    memory = "32Mi";
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
                  "/data"
                  "--addr"
                  "0.0.0.0:8080"
                ];
                env = [
                  {
                    name = "RCLONE_AUTH_KEY";
                    value = "\"user,pass\"";
                  }
                ];
                volumeMounts = [
                  {
                    name = "rclone-serve-staging";
                    mountPath = "/data";
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

  homelab.rcloneBackups.jobs.postgres = {
    inherit namespace;
    schedule = "30 1 * * *";
    source = "/data/postgres";
    destination = "postgres";
    command = "copy";
    versioned = false;
    retention = "30d";
    volumes = [
      {
        name = "postgres-staging";
        persistentVolumeClaim = {
          claimName = "rclone-serve-staging-rclone-serve-0";
          readOnly = true;
        };
      }
    ];
    volumeMounts = [
      {
        name = "postgres-staging";
        mountPath = "/data";
        readOnly = true;
      }
    ];
  };
}
