{ config, ... }:
let
  namespace = "prometheus-stack";
  grafana-oauth-secret = "grafana-oauth";
in
{
  sops = {
    secrets = {
      grafanaClientId = { };
      grafanaClientSecret = { };
    };
    templates.grafana-oauth = {
      content = builtins.toJSON {
        apiVersion = "v1";
        kind = "Secret";
        metadata = {
          name = grafana-oauth-secret;
          namespace = namespace;
        };
        stringData = {
          GF_AUTH_GENERIC_OAUTH_CLIENT_ID = config.sops.placeholder.grafanaClientId;
          GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET = config.sops.placeholder.grafanaClientSecret;
        };
      };
      path = "/var/lib/rancher/k3s/server/manifests/grafana-oauth.json";
    };
  };
  services.k3s.autoDeployCharts.prometheus-stack = {
    name = "kube-prometheus-stack";
    repo = "https://prometheus-community.github.io/helm-charts";
    version = "80.11.1";
    hash = "sha256-V3T8IJ69CV5e5moKl+GpaxUuCMy7fFERWZeNT3qbxfI=";
    targetNamespace = namespace;
    createNamespace = true;
    values = {
      alertmanager = {
        alertmanagerSpec = {
          externalUrl = "https://alertmanager.home.iverian.ru";
          storage.volumeClaimTemplate.spec = {
            accessModes = [ "ReadWriteOnce" ];
            resources.requests.storage = "1Gi";
            selector = { };
          };
        };
        route.main = {
          enabled = true;
          hostnames = [ "alertmanager.home.iverian.ru" ];
          parentRefs = [
            {
              name = "main";
              namespace = "envoy-gateway-system";
            }
          ];
        };
      };
      prometheus = {
        prometheusSpec.storageSpec.volumeClaimTemplate.spec = {
          accessModes = [ "ReadWriteOnce" ];
          resources.requests.storage = "1Gi";
          selector = { };
        };
        route.main = {
          enabled = true;
          hostnames = [ "prometheus.home.iverian.ru" ];
          parentRefs = [
            {
              name = "main";
              namespace = "envoy-gateway-system";
            }
          ];
        };
      };
      grafana = {
        envFromSecret = grafana-oauth-secret;
        envValueFrom = {
          GF_DATABASE_USER = {
            secretKeyRef = {
              name = "postgres-grafana-db";
              key = "username";
            };
          };
          GF_DATABASE_PASSWORD = {
            secretKeyRef = {
              name = "postgres-grafana-db";
              key = "password";
            };
          };
        };
        env = {
          GF_SERVER_ROOT_URL = "https://grafana.home.iverian.ru";
          GF_DATABASE_TYPE = "postgres";
          GF_DATABASE_HOST = "grafana-db";
          GF_DATABASE_SSL_MODE = "require";
          GF_AUTH_GENERIC_OAUTH_ENABLED = "true";
          GF_AUTH_GENERIC_OAUTH_AUTO_LOGIN = "true";
          GF_AUTH_GENERIC_OAUTH_SKIP_ORG_ROLE_SYNC = "true";
          GF_AUTH_GENERIC_OAUTH_EMPTY_SCOPES = "false";
          GF_AUTH_GENERIC_OAUTH_AUTH_URL = "https://auth.home.iverian.ru/api/oidc/authorization";
          GF_AUTH_GENERIC_OAUTH_TOKEN_URL = "https://auth.home.iverian.ru/api/oidc/token";
          GF_AUTH_GENERIC_OAUTH_API_URL = "https://auth.home.iverian.ru/api/oidc/userinfo";
          GF_AUTH_GENERIC_OAUTH_LOGIN_ATTRIBUTE_PATH = "preferred_username";
          GF_AUTH_GENERIC_OAUTH_GROUPS_ATTRIBUTE_PATH = "groups";
          GF_AUTH_GENERIC_OAUTH_NAME_ATTRIBUTE_PATH = "name";
          GF_AUTH_GENERIC_OAUTH_USE_PKCE = "true";
          GF_AUTH_GENERIC_OAUTH_ROLE_ATTRIBUTE_PATH = "";
          GF_AUTH_GENERIC_OAUTH_SCOPES = "openid profile email groups";
        };
        route.main = {
          enabled = true;
          hostnames = [ "grafana.home.iverian.ru" ];
          parentRefs = [
            {
              name = "main";
              namespace = "envoy-gateway-system";
            }
          ];
        };
      };
    };
  };
  services.k3s.manifests = {
    grafana-postgresql.content = {
      apiVersion = "acid.zalan.do/v1";
      kind = "postgresql";
      metadata = {
        name = "grafana-db";
        namespace = namespace;
      };
      spec = {
        teamId = "main";
        volume = {
          size = "1Gi";
        };
        numberOfInstances = 1;
        preparedDatabases.grafana = { };
        postgresql.version = "17";
      };
    };
    prometheus-stack-extauthz.content = {
      apiVersion = "gateway.envoyproxy.io/v1alpha1";
      kind = "SecurityPolicy";
      metadata = {
        name = "extauthz";
        namespace = namespace;
      };
      spec = {
        targetRefs = [
          {
            group = "gateway.networking.k8s.io";
            kind = "HTTPRoute";
            name = "prometheus-stack-kube-prom-alertmanager";
          }
          {
            group = "gateway.networking.k8s.io";
            kind = "HTTPRoute";
            name = "prometheus-stack-kube-prom-prometheus";
          }
        ];
        extAuth = {
          headersToExtAuth = [
            "accept"
            "cookie"
            "authorization"
            "header-authorization"
            "x-forwarded-proto"
          ];
          failOpen = false;
          http = {
            backendRefs = [
              {
                name = "authelia";
                namespace = "authelia";
                port = 80;
              }
            ];
            path = "/api/authz/ext-authz/";
            headersToBackend = [
              "Remote-User"
              "Remote-Groups"
              "Remote-Name"
              "Remote-Email"
            ];
          };
        };
      };
    };
  };
}
