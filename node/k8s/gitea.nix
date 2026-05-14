{ config, ... }:
let
  namespace = "gitea";
  rclone-config = "gitea-rclone-config";
in
{
  sops = {
    secrets = {
      giteaAdminPassword = { };
      giteaOidcClientSecret = { };
      giteaActRunnerToken = { };
      giteaSecretKey = { };
      giteaInternalToken = { };
    };
    templates = {
      gitea-rclone-config = {
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
        path = "/var/lib/rancher/k3s/server/manifests/gitea-rclone-config.json";
      };
      gitea-admin-secret = {
        content = builtins.toJSON {
          apiVersion = "v1";
          kind = "Secret";
          metadata = {
            name = "gitea-admin";
            namespace = namespace;
          };
          stringData = {
            username = "gitea_admin";
            password = config.sops.placeholder.giteaAdminPassword;
            email = "gitea@home.iverian.ru";
          };
        };
        path = "/var/lib/rancher/k3s/server/manifests/gitea-admin-secret.json";
      };
      gitea-oauth-secret = {
        content = builtins.toJSON {
          apiVersion = "v1";
          kind = "Secret";
          metadata = {
            name = "gitea-authelia-oauth";
            namespace = namespace;
          };
          stringData = {
            key = "gitea";
            secret = config.sops.placeholder.giteaOidcClientSecret;
          };
        };
        path = "/var/lib/rancher/k3s/server/manifests/gitea-oauth-secret.json";
      };
      gitea-act-runner-token = {
        content = builtins.toJSON {
          apiVersion = "v1";
          kind = "Secret";
          metadata = {
            name = "gitea-act-runner-token";
            namespace = namespace;
          };
          stringData = {
            token = config.sops.placeholder.giteaActRunnerToken;
          };
        };
        path = "/var/lib/rancher/k3s/server/manifests/gitea-act-runner-token.json";
      };
      gitea-security = {
        content = builtins.toJSON {
          apiVersion = "v1";
          kind = "Secret";
          metadata = {
            name = "gitea-security";
            namespace = namespace;
          };
          stringData = {
            secretKey = config.sops.placeholder.giteaSecretKey;
            internalToken = config.sops.placeholder.giteaInternalToken;
          };
        };
        path = "/var/lib/rancher/k3s/server/manifests/gitea-security-secret.json";
      };
    };
  };

  services.k3s.manifests = {
    gitea-postgresql.content = {
      apiVersion = "acid.zalan.do/v1";
      kind = "postgresql";
      metadata = {
        name = "gitea-db";
        namespace = namespace;
      };
      spec = {
        teamId = "main";
        volume = {
          size = "5Gi";
        };
        numberOfInstances = 1;
        preparedDatabases.gitea = { };
        postgresql.version = "17";
        enableLogicalBackup = true;
      };
    };

    gitea-httproute.content = {
      apiVersion = "gateway.networking.k8s.io/v1";
      kind = "HTTPRoute";
      metadata = {
        name = "gitea";
        namespace = namespace;
      };
      spec = {
        parentRefs = [
          {
            name = "main";
            namespace = "envoy-gateway-system";
          }
          {
            name = "public";
            namespace = "envoy-gateway-system";
          }
        ];
        hostnames = [
          "gitea.iverian.ru"
        ];
        rules = [
          {
            backendRefs = [
              {
                name = "gitea-http";
                port = 3000;
              }
            ];
          }
        ];
      };
    };

    gitea-act-runner.content = {
      apiVersion = "apps/v1";
      kind = "StatefulSet";
      metadata = {
        name = "act-runner";
        namespace = namespace;
        labels.app = "act-runner";
      };
      spec = {
        replicas = 1;
        serviceName = "act-runner";
        selector.matchLabels.app = "act-runner";
        template = {
          metadata.labels.app = "act-runner";
          spec = {
            securityContext.fsGroup = 1000;
            containers = [
              {
                name = "runner";
                image = "gitea/act_runner:nightly-dind-rootless";
                imagePullPolicy = "Always";
                env = [
                  {
                    name = "DOCKER_HOST";
                    value = "tcp://localhost:2376";
                  }
                  {
                    name = "DOCKER_CERT_PATH";
                    value = "/certs/client";
                  }
                  {
                    name = "DOCKER_TLS_VERIFY";
                    value = "1";
                  }
                  {
                    name = "GITEA_INSTANCE_URL";
                    value = "http://gitea-http.${namespace}.svc.cluster.local:3000";
                  }
                  {
                    name = "GITEA_RUNNER_REGISTRATION_TOKEN";
                    valueFrom.secretKeyRef = {
                      name = "gitea-act-runner-token";
                      key = "token";
                    };
                  }
                ];
                securityContext.privileged = true;
                volumeMounts = [
                  {
                    name = "runner-data";
                    mountPath = "/data";
                  }
                ];
              }
            ];
          };
        };
        volumeClaimTemplates = [
          {
            metadata.name = "runner-data";
            spec = {
              accessModes = [ "ReadWriteOnce" ];
              storageClassName = "local-path";
              resources.requests.storage = "1Gi";
            };
          }
        ];
      };
    };
    gitea-rclone-backup.content = {
      apiVersion = "batch/v1";
      kind = "CronJob";
      metadata = {
        name = "rclone-backup";
        namespace = namespace;
      };
      spec = {
        schedule = "0 2 * * *";
        concurrencyPolicy = "Forbid";
        successfulJobsHistoryLimit = 3;
        failedJobsHistoryLimit = 3;
        jobTemplate.spec.template = {
          spec = {
            restartPolicy = "OnFailure";
            volumes = [
              {
                name = "config-ro";
                secret.secretName = rclone-config;
              }
              {
                name = "state";
                emptyDir = { };
              }
              {
                name = "gitea-data";
                persistentVolumeClaim = {
                  claimName = "gitea-shared-storage";
                  readOnly = true;
                };
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
                args = [ "cp /config-ro/rclone.conf /state/rclone.conf" ];
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
                  "/data/git/gitea-repositories"
                  "crypt:gitea"
                  "--config"
                  "/state/rclone.conf"
                  "--log-level"
                  "INFO"
                  "--delete-during"
                ];
                volumeMounts = [
                  {
                    name = "state";
                    mountPath = "/state";
                  }
                  {
                    name = "gitea-data";
                    mountPath = "/data";
                    readOnly = true;
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

  services.k3s.autoDeployCharts.gitea = {
    name = "gitea";
    repo = "https://dl.gitea.com/charts";
    version = "12.5.0";
    hash = "sha256-LW8189H/DPyrDyIULSCh1kBfqXSnnXoYAAkE0jMTGCM=";
    targetNamespace = namespace;
    createNamespace = true;
    values = {
      persistence = {
        enabled = true;
        storageClass = "storage";
        size = "10Gi";
      };

      "postgresql-ha".enabled = false;
      postgresql.enabled = false;
      valkey-cluster.enabled = false;
      valkey.enabled = true;

      gitea = {
        admin.existingSecret = "gitea-admin";

        config = {
          database = {
            DB_TYPE = "postgres";
            HOST = "gitea-db:5432";
            NAME = "gitea";
            USER = "postgres";
            SSL_MODE = "require";
          };
          server = {
            DOMAIN = "gitea.iverian.ru";
            ROOT_URL = "https://gitea.iverian.ru";
            DISABLE_SSH = "true";
          };
          openid = {
            ENABLE_OPENID_SIGNIN = "false";
            ENABLE_OPENID_SIGNUP = "true";
          };
          service = {
            DISABLE_REGISTRATION = "false";
            ALLOW_ONLY_EXTERNAL_REGISTRATION = "true";
            SHOW_REGISTRATION_BUTTON = "false";
            REQUIRE_SIGNIN_VIEW = "true";
            DEFAULT_KEEP_EMAIL_PRIVATE = "true";
            ENABLE_PASSKEY_AUTHENTICATION = "false";
            ENABLE_PASSWORD_SIGNIN_FORM = "false";
          };
          "service.explore" = {
            DISABLE_USERS_PAGE = "true";
            DISABLE_ORGANIZATIONS_PAGE = "true";
          };
          repository = {
            USE_COMPAT_SSH_URI = "true";
            DEFAULT_PRIVATE = "true";
          };
          webhook = {
            ALLOWED_HOST_LIST = "private";
          };
          cors = {
            ENABLED = "true";
            ALLOW_DOMAIN = "https://gitea.iverian.ru";
            ALLOW_SUBDOMAIN = "false";
            X_FRAME_OPTIONS = "SAMEORIGIN";
          };
          actions = {
            ENABLED = "true";
          };
          ui = {
            SHOW_USER_EMAIL = "false";
          };
          "repository.pull-request" = {
            DEFAULT_MERGE_STYLE = "fast-forward-only";
          };
        };

        additionalConfigFromEnvs = [
          {
            name = "GITEA__DATABASE__PASSWD";
            valueFrom.secretKeyRef = {
              name = "postgres-gitea-db";
              key = "password";
            };
          }
          {
            name = "GITEA__SECURITY__SECRET_KEY";
            valueFrom.secretKeyRef = {
              name = "gitea-security";
              key = "secretKey";
            };
          }
          {
            name = "GITEA__SECURITY__INTERNAL_TOKEN";
            valueFrom.secretKeyRef = {
              name = "gitea-security";
              key = "internalToken";
            };
          }
        ];

        oauth = [
          {
            name = "authelia";
            provider = "openidConnect";
            existingSecret = "gitea-authelia-oauth";
            useCustomUrls = true;
            customAuthUrl = "https://auth.iverian.ru/api/oidc/authorization";
            customTokenUrl = "https://auth.iverian.ru/api/oidc/token";
            customProfileUrl = "http://auth.iverian.ru/api/oidc/userinfo";
          }
        ];
      };
    };
  };
}
