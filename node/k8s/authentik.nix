{ config, ... }:
let
  namespace = "authentik";
in
{
  services.k3s.autoDeployCharts.authentik = {
    name = "authentik";
    repo = "https://charts.goauthentik.io";
    version = "2025.10.3";
    hash = "sha256-mnY7Jmnc1rbnyKew18S7WpOXHGHalWtNbSzJryFg/Fk=";
    targetNamespace = namespace;
    createNamespace = true;
    values = {
      global = {
        env = [
          {
            name = "AUTHENTIK_POSTGRESQL__SSLMODE";
            value = "prefer";
          }
          {
            name = "AUTHENTIK_POSTGRESQL__DISABLE_SERVER_SIDE_CURSORS";
            value = "true";
          }
        ];
      };
      authentik = {
        secret_key = "file:///secret-key/value";
        postgresql = {
          host = "authentik-postgres-pooler";
          name = "authentik";
          user = "file:///postgres-creds/username";
          password = "file:///postgres-creds/password";
        };
      };
      metrics = {
        enabled = true;
        # serviceMonitor.enabled = true;
      };
      server = {
        ingress = {
          enabled = true;
          annotations = {
            "cert-manager.io/cluster-issuer" = "letsencrypt";
          };
          hosts = [ "authentik.home.iverian.ru" ];
          tls = [
            {
              hosts = [ "authentik.home.iverian.ru" ];
              secretName = "authentik-tls";
            }
          ];
        };
        volumes = [
          {
            name = "postgres-creds";
            secret = {
              secretName = "postgres.authentik-postgres.credentials.postgresql.acid.zalan.do";
            };
          }
          {
            name = "secret-key";
            secret = {
              secretName = "authentik-secret-key";
            };
          }
        ];
        volumeMounts = [
          {
            name = "postgres-creds";
            mountPath = "/postgres-creds";
            readOnly = true;
          }
          {
            name = "secret-key";
            mountPath = "/secret-key";
            readOnly = true;
          }
        ];
      };
      worker = {
        volumes = [
          {
            name = "postgres-creds";
            secret = {
              secretName = "postgres.authentik-postgres.credentials.postgresql.acid.zalan.do";
            };
          }
          {
            name = "secret-key";
            secret = {
              secretName = "authentik-secret-key";
            };
          }
        ];
        volumeMounts = [
          {
            name = "postgres-creds";
            mountPath = "/postgres-creds";
            readOnly = true;
          }
          {
            name = "secret-key";
            mountPath = "/secret-key";
            readOnly = true;
          }
        ];
      };
    };
  };
  services.k3s.manifests = {
    authentik-postgresql.content = {
      apiVersion = "acid.zalan.do/v1";
      kind = "postgresql";
      metadata = {
        name = "authentik-postgres";
        namespace = namespace;
      };
      spec = {
        teamId = "main";
        connectionPooler = {
          numberOfInstances = 1;
          mode = "transaction";
        };
        volume = {
          size = "1Gi";
        };
        numberOfInstances = 1;
        preparedDatabases.authentik = { };
        postgresql.version = "17";
      };
    };
  };
  sops = {
    secrets = {
      authentikSecretKey = { };
    };
    templates.authentik-secret-key = {
      content = builtins.toJSON {
        apiVersion = "v1";
        kind = "Secret";
        metadata = {
          name = "authentik-secret-key";
          namespace = namespace;
        };
        stringData = {
          value = config.sops.placeholder.authentikSecretKey;
        };
      };
      path = "/var/lib/rancher/k3s/server/manifests/authentik-secret-key.json";
    };
  };
}
