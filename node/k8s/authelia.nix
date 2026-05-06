{ config, ... }:
let
  namespace = "authelia";
in
{
  sops = {
    secrets = {
      autheliaSessionEncryptionKey = { };
      autheliaDatabaseEncryptionKey = { };
      autheliaDatabase = { };
      autheliaJwksKey = { };
      autheliaHmacKey = { };
      autheliaResetPasswordKey = { };
    };
    templates.authelia-data = {
      content = builtins.toJSON {
        apiVersion = "v1";
        kind = "Secret";
        metadata = {
          name = "authelia-data";
          namespace = namespace;
        };
        data = {
          databaseEncryptionKey = config.sops.placeholder.autheliaDatabaseEncryptionKey;
          sessionEncryptionKey = config.sops.placeholder.autheliaSessionEncryptionKey;
          resetPasswordKey = config.sops.placeholder.autheliaResetPasswordKey;
          jwksKey = config.sops.placeholder.autheliaJwksKey;
          hmacKey = config.sops.placeholder.autheliaHmacKey;
          database = config.sops.placeholder.autheliaDatabase;
        };
      };
      path = "/var/lib/rancher/k3s/server/manifests/authelia-secret.json";
    };
  };
  services.k3s.manifests = {
    authelia-postgresql.content = {
      apiVersion = "acid.zalan.do/v1";
      kind = "postgresql";
      metadata = {
        name = "authelia-db";
        namespace = namespace;
      };
      spec = {
        teamId = "main";
        volume = {
          size = "1Gi";
        };
        numberOfInstances = 1;
        preparedDatabases.authelia = { };
        postgresql.version = "17";
      };
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
        gatewayAPI = {
          enabled = true;
          parentRefs = [
            {
              name = "main";
              namespace = "envoy-gateway-system";
            }
          ];
        };
      };
      configMap = {
        storage = {
          encryption_key = {
            secret_name = "authelia-data";
            path = "databaseEncryptionKey";
          };
          postgres = {
            enabled = true;
            deploy = false;
            address = "tcp://authelia-db";
            database = "authelia";
            username = "postgres";
            password = {
              secret_name = "postgres-authelia-db";
              path = "password";
            };
            tls = {
              enabled = true;
              skip_verify = true;
            };
          };
        };
        session = {
          same_site = "strict";
          encryption_key = {
            secret_name = "authelia-data";
            path = "sessionEncryptionKey";
          };
          cookies = [
            {
              domain = "auth.iverian.ru";
            }
          ];
        };
        webauthn = {
          enable_passkey_login = true;
        };
        access_control.default_policy = "one_factor";
        notifier = {
          disable_startup_check = true;
          filesystem = {
            enabled = true;
            filename = "/config/notification.txt";
          };
        };
        identity_validation.reset_password.secret = {
          secret_name = "authelia-data";
          path = "resetPasswordKey";
        };
        identity_providers = {
          oidc = {
            enabled = true;
            hmac_secret = {
              secret_name = "authelia-data";
              path = "hmacKey";
            };
            jwks = [
              {
                key_id = "auth";
                algorithm = "RS256";
                use = "sig";
                key.path = "/secrets/authelia-data/jwksKey";
              }
            ];
            claims_policies = {
              grafana.id_token = [
                "email"
                "name"
                "groups"
                "preferred_username"
              ];
            };
            clients = [
              {
                client_id = "grafana";
                client_secret = "$pbkdf2-sha512$310000$glwqEtxfkikIqilXQtbV5w$mXIDhHzYc48iuLVjg4pR.239W1fO42gFXWsaWijmF/Joq7dHpOwAv6pF3/hjZKoWxy8dFkyq/yUZ2XO4pYnNdA";
                public = false;
                require_pkce = true;
                pkce_challenge_method = "S256";
                authorization_policy = "one_factor";
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
                consent_mode = "implicit";
              }
              {
                client_id = "gitea";
                client_secret = "$pbkdf2-sha512$310000$FTwibf/9uyjN6SUph5xRXg$BrIbOjQi1V8SrXQUOuMVfaBY64zOV.pi04DoDE8GDbpuAKPvvYf7ra9Gww9vaAJddTDTBmLUnd7LKzWY59GkWA";
                public = false;
                require_pkce = false;
                pkce_challenge_method = "";
                authorization_policy = "one_factor";
                redirect_uris = [
                  "https://gitea.iverian.ru/user/oauth2/authelia/callback"
                ];
                scopes = [
                  "openid"
                  "profile"
                  "email"
                ];
                grant_types = [ "authorization_code" ];
                response_types = [ "code" ];
                access_token_signed_response_alg = "none";
                userinfo_signed_response_alg = "none";
                token_endpoint_auth_method = "client_secret_basic";
                consent_mode = "implicit";
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
