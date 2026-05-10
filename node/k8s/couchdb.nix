{ config, ... }:
let
  namespace = "couchdb";
  rclone-config = "couchdb-rclone-config";
in
{
  sops = {
    secrets = {
      couchdbAdminPassword = { };
      couchdbCookieAuthSecret = { };
      couchdbErlangCookie = { };
      rcloneConfigB64 = { };
    };
    templates = {
      couchdb-admin = {
        content = builtins.toJSON {
          apiVersion = "v1";
          kind = "Secret";
          metadata = {
            name = "couchdb-admin";
            namespace = namespace;
          };
          stringData = {
            adminUsername = "admin";
            adminPassword = config.sops.placeholder.couchdbAdminPassword;
            cookieAuthSecret = config.sops.placeholder.couchdbCookieAuthSecret;
            erlangCookie = config.sops.placeholder.couchdbErlangCookie;
          };
        };
        path = "/var/lib/rancher/k3s/server/manifests/couchdb-admin-secret.json";
      };
      couchdb-rclone-config = {
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
        path = "/var/lib/rancher/k3s/server/manifests/couchdb-rclone-config.json";
      };
    };
  };

  services.k3s.manifests = {
    couchdb-namespace.content = {
      apiVersion = "v1";
      kind = "Namespace";
      metadata.name = namespace;
    };

    couchdb-httproute.content = {
      apiVersion = "gateway.networking.k8s.io/v1";
      kind = "HTTPRoute";
      metadata = {
        name = "couchdb";
        namespace = namespace;
      };
      spec = {
        parentRefs = [
          {
            name = "external";
            namespace = "envoy-gateway-system";
          }
          {
            name = "main";
            namespace = "envoy-gateway-system";
          }
        ];
        hostnames = [ "sync.iverian.ru" ];
        rules = [
          # Block admin UI and node management — redirect away rather than expose
          {
            matches = [
              {
                path = {
                  type = "PathPrefix";
                  value = "/_utils";
                };
              }
              {
                path = {
                  type = "PathPrefix";
                  value = "/_node";
                };
              }
              {
                path = {
                  type = "PathPrefix";
                  value = "/_up";
                };
              }
            ];
            filters = [
              {
                type = "RequestRedirect";
                requestRedirect = {
                  statusCode = 301;
                  path = {
                    type = "ReplaceFullPath";
                    replaceFullPath = "/";
                  };
                };
              }
            ];
          }
          {
            backendRefs = [
              {
                name = "couchdb-svc-couchdb";
                port = 5984;
              }
            ];
          }
        ];
      };
    };

    couchdb-backend-policy.content = {
      apiVersion = "gateway.envoyproxy.io/v1alpha1";
      kind = "BackendTrafficPolicy";
      metadata = {
        name = "couchdb-timeout";
        namespace = namespace;
      };
      spec = {
        targetRefs = [
          {
            group = "gateway.networking.k8s.io";
            kind = "HTTPRoute";
            name = "couchdb";
          }
        ];
        timeout.http.requestTimeout = "1h";
      };
    };

    couchdb-rclone-backup.content = {
      apiVersion = "batch/v1";
      kind = "CronJob";
      metadata = {
        name = "rclone-backup";
        namespace = namespace;
      };
      spec = {
        schedule = "0 4 * * *";
        concurrencyPolicy = "Forbid";
        successfulJobsHistoryLimit = 3;
        failedJobsHistoryLimit = 3;
        jobTemplate.spec.template = {
          metadata.annotations."reloader.stakater.com/auto" = "true";
          spec = {
            restartPolicy = "OnFailure";
            volumes = [
              {
                name = "couchdb-data";
                persistentVolumeClaim = {
                  claimName = "database-storage-couchdb-couchdb-0";
                  readOnly = true;
                };
              }
              {
                name = "config-ro";
                secret.secretName = rclone-config;
              }
              {
                name = "state";
                emptyDir = { };
              }
            ];
            initContainers = [
              {
                name = "setup";
                image = "rancher/mirrored-library-busybox:1.36.1";
                command = [
                  "sh"
                  "-c"
                ];
                args = [ "cp /config-ro/rclone.conf /state/rclone.conf && mkdir -p /state/cache" ];
                volumeMounts = [
                  {
                    name = "config-ro";
                    mountPath = "/config-ro";
                  }
                  {
                    name = "state";
                    mountPath = "/state";
                  }
                ];
                resources = {
                  requests = {
                    cpu = "50m";
                    memory = "64Mi";
                  };
                  limits = {
                    cpu = "100m";
                    memory = "128Mi";
                  };
                };
              }
            ];
            containers = [
              {
                name = "rclone";
                image = "rclone/rclone:sha-0157a1f";
                args = [
                  "sync"
                  "/data"
                  "crypt:couchdb"
                  "--config"
                  "/state/rclone.conf"
                  "--cache-dir"
                  "/state/cache"
                  "--log-level"
                  "INFO"
                  "--delete-during"
                ];
                volumeMounts = [
                  {
                    name = "couchdb-data";
                    mountPath = "/data";
                    readOnly = true;
                  }
                  {
                    name = "state";
                    mountPath = "/state";
                  }
                ];
                resources = {
                  requests = {
                    cpu = "100m";
                    memory = "256Mi";
                  };
                  limits = {
                    cpu = "1000m";
                    memory = "1Gi";
                  };
                };
              }
            ];
          };
        };
      };
    };
  };

  services.k3s.autoDeployCharts.couchdb = {
    name = "couchdb";
    repo = "https://apache.github.io/couchdb-helm/";
    version = "4.6.3";
    hash = "sha256-M6AorHYpPAOdOC1QeAD0UQ3Bo62AUPHUPy5hsucTiGQ=";
    targetNamespace = namespace;
    createNamespace = false;
    values = {
      clusterSize = 1;
      fullnameOverride = "couchdb";
      createAdminSecret = false;
      extraSecretName = "couchdb-admin";
      adminUsernameKey = "adminUsername";
      adminPasswordKey = "adminPassword";
      cookieAuthSecretKey = "cookieAuthSecret";
      erlangCookieKey = "erlangCookie";

      autoSetup = {
        enabled = true;
        defaultDatabases = [
          "obsidian"
          "_global_changes"
          "_replicator"
          "_users"
        ];
      };

      persistentVolume = {
        enabled = true;
        size = "10Gi";
        storageClass = "local-path";
      };

      service = {
        enabled = true;
        type = "ClusterIP";
        externalPort = 5984;
      };

      ingress.enabled = false;

      couchdbConfig = {
        couchdb.uuid = "019e10bb-0955-7223-bd79-a5130a5c83aa";
        chttpd = {
          require_valid_user = "true";
        };
        httpd = {
          enable_cors = "true";
        };
        cors = {
          origins = "*";
          credentials = "true";
          headers = "accept, authorization, content-type, origin, referer";
          methods = "GET, PUT, POST, HEAD, DELETE";
        };
      };
    };
  };
}
