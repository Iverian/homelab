{ config, ... }:
let
  namespace = "cert-manager";
  secret = "cloudflare-api-key";
in
{
  sops = {
    secrets = {
      cloudflareApiKey = { };
      cloudflareEmail = { };
    };
    templates = {
      cloudflare-api-key = {
        content = builtins.toJSON {
          apiVersion = "v1";
          kind = "Secret";
          metadata = {
            name = secret;
            namespace = namespace;
          };
          stringData = {
            key = config.sops.placeholder.cloudflareApiKey;
          };
        };
        path = "/var/lib/rancher/k3s/server/manifests/cloudflare-api-key.json";
      };
      letsencrypt-issuer = {
        content = {
          apiVersion = "cert-manager.io/v1";
          kind = "ClusterIssuer";
          metadata = {
            name = "letsencrypt";
            namespace = namespace;
          };
          spec = {
            acme = {
              email = config.sops.placeholder.cloudflareEmail;
              server = "https://acme-v02.api.letsencrypt.org/directory";
              privateKeySecretRef = {
                name = "issuer-account-key";
              };
              solvers = [
                {
                  dns01 = {
                    cloudflare = {
                      email = config.sops.placeholder.cloudflareEmail;
                      apiTokenSecretRef = {
                        name = secret;
                        key = "key";
                      };
                    };
                  };
                }
              ];
            };
          };
        };
        path = "/var/lib/rancher/k3s/server/manifests/letsencrypt-issuer.json";
      };
    };
  };
  services.k3s.autoDeployCharts.cert-manager = {
    repo = "oci://quay.io/jetstack/charts/cert-manager";
    version = "1.19.2";
    hash = "sha256-h+La+pRr0FxWvol7L+LhcfK7+tlsnUhAnUsRiNJAr28=";
    targetNamespace = namespace;
    createNamespace = true;
    values = {
      crds = {
        enabled = true;
        keep = false;
      };
      # prometheus = {
      #   enabled = false;
      #   servicemonitor.enabled = false;
      # };
    };
  };
}
