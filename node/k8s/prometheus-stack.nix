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
        ingress = {
          enabled = true;
          annotations = {
            "cert-manager.io/cluster-issuer" = "letsencrypt";
          };
          hosts = [ "alertmanager.home.iverian.ru" ];
          tls = [
            {
              hosts = [ "alertmanager.home.iverian.ru" ];
              secretName = "alertmanager-tls";
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
        ingress = {
          enabled = true;
          annotations = {
            "cert-manager.io/cluster-issuer" = "letsencrypt";
          };
          hosts = [ "prometheus.home.iverian.ru" ];
          tls = [
            {
              hosts = [ "prometheus.home.iverian.ru" ];
              secretName = "prometheus-tls";
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
          GF_DATABASE_HOST = "grafana-db-0.grafana.pod";
          GF_DATABASE_SSL_MODE = "require";
          GF_AUTH_GENERIC_OAUTH_AUTH_URL = "https://authentik.home.iverian.ru/application/o/authorize/";
          GF_AUTH_GENERIC_OAUTH_TOKEN_URL = "https://authentik.home.iverian.ru/application/o/token/";
          GF_AUTH_GENERIC_OAUTH_API_URL = "https://authentik.home.iverian.ru/application/o/userinfo/";
          GF_AUTH_SIGNOUT_REDIRECT_URL = "https://authentik.home.iverian.ru/application/o/grafana/end-session/";
          GF_AUTH_GENERIC_OAUTH_ENABLED = "true";
          GF_AUTH_GENERIC_OAUTH_AUTO_LOGIN = "true";
          GF_AUTH_GENERIC_OAUTH_SKIP_ORG_ROLE_SYNC = "true";
          GF_AUTH_GENERIC_OAUTH_SCOPES = "openid profile email";
        };
        ingress = {
          enabled = true;
          annotations = {
            "cert-manager.io/cluster-issuer" = "letsencrypt";
          };
          hosts = [ "grafana.home.iverian.ru" ];
          tls = [
            {
              hosts = [ "grafana.home.iverian.ru" ];
              secretName = "grafana-tls";
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
  };
}
