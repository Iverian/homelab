{ config, ... }:
let
  namespace = "gitea";
in
{
  sops = {
    secrets = {
      giteaAdminPassword = { };
      giteaOidcClientSecret = { };
      giteaActRunnerToken = { };
    };
    templates = {
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
            sectionName = "private-secure";
          }
        ];
        hostnames = [ "gitea.home.iverian.ru" ];
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
            SSH_PORT = 22;
            SSH_LISTEN_PORT = 2222;
            DOMAIN = "gitea.home.iverian.ru";
            ROOT_URL = "https://gitea.home.iverian.ru";
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
          };
          repository = {
            USE_COMPAT_SSH_URI = "true";
          };
          actions = {
            ENABLED = "true";
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
        ];

        oauth = [
          {
            name = "authelia";
            provider = "openidConnect";
            existingSecret = "gitea-authelia-oauth";
            autoDiscoverUrl = "https://auth.home.iverian.ru/.well-known/openid-configuration";
          }
        ];
      };
    };
  };

  services.k3s.manifests = {
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
  };
}
