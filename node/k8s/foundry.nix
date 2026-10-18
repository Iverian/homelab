{ config, ... }:
let
  namespace = "foundry";
  secrets = "foundry-secrets";
  version = "14.365.0";
in
{
  sops = {
    secrets = {
      foundryKey = { };
      foundryAdminKey = { };
      foundryUsername = { };
      foundryPassword = { };
    };
    templates = {
      foundry-secrets = {
        content = builtins.toJSON {
          apiVersion = "v1";
          kind = "Secret";
          metadata = {
            name = secrets;
            namespace = namespace;
          };
          stringData = {
            licenseKey = config.sops.placeholder.foundryKey;
            adminKey = config.sops.placeholder.foundryAdminKey;
            username = config.sops.placeholder.foundryUsername;
            password = config.sops.placeholder.foundryPassword;
          };
        };
        path = "/var/lib/rancher/k3s/server/manifests/foundry-secrets.json";
      };
    };
  };

  services.k3s.manifests = {
    foundry-namespace.content = {
      apiVersion = "v1";
      kind = "Namespace";
      metadata.name = namespace;
    };

    foundry-data.content = {
      apiVersion = "v1";
      kind = "PersistentVolumeClaim";
      metadata = {
        name = "foundry-data";
        namespace = namespace;
      };
      spec = {
        accessModes = [ "ReadWriteOnce" ];
        storageClassName = "storage";
        resources.requests.storage = "20Gi";
      };
    };

    foundry-deployment.content = {
      apiVersion = "apps/v1";
      kind = "Deployment";
      metadata = {
        name = "foundry";
        namespace = namespace;
        labels.app = "foundry";
      };
      spec = {
        replicas = 1;
        strategy.type = "Recreate";
        selector.matchLabels.app = "foundry";
        template = {
          metadata = {
            labels.app = "foundry";
            annotations."reloader.stakater.com/auto" = "true";
          };
          spec = {
            hostname = "foundry";
            volumes = [
              {
                name = "data";
                persistentVolumeClaim.claimName = "foundry-data";
              }
            ];
            containers = [
              {
                name = "foundry";
                image = "ghcr.io/felddy/foundryvtt:${version}";
                env = [
                  {
                    name = "FOUNDRY_LICENSE_KEY";
                    valueFrom.secretKeyRef = {
                      name = secrets;
                      key = "licenseKey";
                    };
                  }
                  {
                    name = "FOUNDRY_ADMIN_KEY";
                    valueFrom.secretKeyRef = {
                      name = secrets;
                      key = "adminKey";
                    };
                  }
                  {
                    name = "FOUNDRY_USERNAME";
                    valueFrom.secretKeyRef = {
                      name = secrets;
                      key = "username";
                    };
                  }
                  {
                    name = "FOUNDRY_PASSWORD";
                    valueFrom.secretKeyRef = {
                      name = secrets;
                      key = "password";
                    };
                  }
                  {
                    name = "CONTAINER_PRESERVE_CONFIG";
                    value = "true";
                  }
                  {
                    name = "CONTAINER_CACHE";
                    value = "/data/container_cache";
                  }
                  {
                    name = "CONTAINER_CACHE_SIZE";
                    value = "1";
                  }
                  {
                    name = "FOUNDRY_VERSION";
                    value = "14.365";
                  }
                  {
                    name = "FOUNDRY_HOSTNAME";
                    value = "foundry.iverian.ru";
                  }
                  {
                    name = "FOUNDRY_PROXY_SSL";
                    value = "true";
                  }
                  {
                    name = "FOUNDRY_PROXY_PORT";
                    value = "443";
                  }
                  {
                    name = "FOUNDRY_UPNP";
                    value = "false";
                  }
                  {
                    name = "FOUNDRY_COMPRESS_WEBSOCKET";
                    value = "true";
                  }
                  {
                    name = "FOUNDRY_TELEMETRY";
                    value = "false";
                  }
                  {
                    name = "TZ";
                    value = "Europe/Moscow";
                  }
                ];
                ports = [
                  {
                    name = "http";
                    containerPort = 30000;
                    protocol = "TCP";
                  }
                ];
                startupProbe = {
                  tcpSocket.port = "http";
                  periodSeconds = 10;
                  failureThreshold = 30;
                };
                readinessProbe = {
                  tcpSocket.port = "http";
                  periodSeconds = 10;
                  failureThreshold = 3;
                };
                livenessProbe = {
                  tcpSocket.port = "http";
                  periodSeconds = 20;
                  failureThreshold = 3;
                };
                resources = {
                  requests = {
                    cpu = "250m";
                    memory = "512Mi";
                  };
                  limits = {
                    cpu = "2";
                    memory = "2Gi";
                  };
                };
                volumeMounts = [
                  {
                    name = "data";
                    mountPath = "/data";
                  }
                ];
              }
            ];
          };
        };
      };
    };

    foundry-service.content = {
      apiVersion = "v1";
      kind = "Service";
      metadata = {
        name = "foundry";
        namespace = namespace;
      };
      spec = {
        selector.app = "foundry";
        ports = [
          {
            name = "http";
            port = 30000;
            targetPort = "http";
            protocol = "TCP";
          }
        ];
      };
    };

    foundry-httproute.content = {
      apiVersion = "gateway.networking.k8s.io/v1";
      kind = "HTTPRoute";
      metadata = {
        name = "foundry";
        namespace = namespace;
      };
      spec = {
        hostnames = [ "foundry.iverian.ru" ];
        parentRefs = [
          {
            name = "main";
            namespace = "envoy-gateway-system";
          }
          {
            name = "external";
            namespace = "envoy-gateway-system";
          }
        ];
        rules = [
          {
            matches = [
              {
                path = {
                  type = "PathPrefix";
                  value = "/";
                };
              }
            ];
            backendRefs = [
              {
                name = "foundry";
                port = 30000;
              }
            ];
          }
        ];
      };
    };

  };

  homelab.rcloneBackups.jobs.foundry = {
    inherit namespace;
    schedule = "0 6 * * *";
    source = "/data";
    excludes = [
      "Logs/**"
      "container_cache/**"
      "Data/modules/**"
      "Data/systems/**"
    ];
    volumes = [
      {
        name = "foundry-data";
        persistentVolumeClaim = {
          claimName = "foundry-data";
          readOnly = true;
        };
      }
    ];
    volumeMounts = [
      {
        name = "foundry-data";
        mountPath = "/data";
        readOnly = true;
      }
    ];
  };
}
