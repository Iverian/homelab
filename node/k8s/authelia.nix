{ config, ... }:
let
  namespace = "authelia";
in
{
  sops = {
    secrets = {
      autheliaEncryptionKey = { };
      autheliaDatabase = { };
    };
    templates.authelia-data = {
      content = builtins.toJSON {
        apiVersion = "v1";
        kind = "Secret";
        metadata = {
          name = "authelia-data";
          namespace = namespace;
        };
        stringData = {
          encryptionKey = config.sops.placeholder.autheliaEncryptionKey;
          database = config.sops.placeholder.autheliaDatabase;
        };
      };
      path = "/var/lib/rancher/k3s/server/manifests/authelia-secret.json";
    };
  };
  services.k3s.manifests.authelia-postgresql.content = {
    apiVersion = "acid.zalan.do/v1";
    kind = "postgresql";
    metadata = {
      name = "authelia-db";
      namespace = namespace;
    };
    spec = {
      teamId = "main";
      connectionPooler = {
        numberOfInstances = 1;
        mode = "session";
      };
      volume = {
        size = "1Gi";
      };
      numberOfInstances = 1;
      preparedDatabases.grafana = { };
      postgresql.version = "17";
    };
  };
  services.k3s.autoDeployCharts.authelia = {
    name = "authelia";
    repo = "https://charts.authelia.com";
    version = "0.10.49";
    hash = "sha256-uqoZfS/NEj0jqynZUhDNAzCtqCNUMmQNszojxZwKC2A=";
    targetNamespace = namespace;
    createNamespace = true;
    values = {
      rbac.enabled = true;
      pod = {
        kind = "Deployment";
        resources = {
          requests.cpu = "100m";
          requests.memory = "256Mi";
          limits.cpu = "500m";
          limits.memory = "512Mi";
        };
      };
      ingress = {
        enabled = true;
        annotations = {
          "cert-manager.io/cluster-issuer" = "letsencrypt";
        };
        tls = {
          enabled = true;
          secret = "authelia-tls";
        };
        traefikCRD = {
          enabled = true;
          disableIngressRoute = true;
        };
      };
      configMap = {
        storage = {
          postgres = {
            enabled = true;
            deploy = false;
            address = "tcp://authelia-db-pooler";
            database = "authelia";
            username = "postgres";
            password = {
              secret_name = "postgres-authelia-db";
              path = "password";
            };
            tls.skip_verify = true;
          };
        };
        session = {
          same_site = "strict";
          encryption_key = {
            secret_name = "authelia-data";
            path = "encryptionKey";
          };
          cookies = [
            {
              domain = "authelia.home.iverian.ru";
            }
          ];
        };
        webauthn = {
          enable_passkey_login = true;
        };
        identity_providers = {
          oidc = {
            clients = [
              {
                client_id = "grafana";
                client_secret = "$pbkdf2-sha512$310000$glwqEtxfkikIqilXQtbV5w$mXIDhHzYc48iuLVjg4pR.239W1fO42gFXWsaWijmF/Joq7dHpOwAv6pF3/hjZKoWxy8dFkyq/yUZ2XO4pYnNdA";
                public = false;
                redirect_uris = [
                  "https://grafana.home.iverian.ru/login/generic_oauth"
                ];
                scopes = [
                  "openid"
                  "profile"
                  "email"
                  "groups"
                ];
                grant_types = [ "authorization_code" ];
                response_types = [ "code" ];
                access_token_signed_response_alg = "none";
                userinfo_signed_response_alg = "none";
                token_endpoint_auth_method = "client_secret_basic";
              }
            ];
          };
        };
        authentication_backend = {
          file = {
            enabled = true;
            path = "/secrets/authelia-data/database";
          };
        };
      };
      secret = {
        additionalSecrets = {
          authelia-data = { };
          "postgres-authelia-db" = { };
        };
      };
    };
  };
}
