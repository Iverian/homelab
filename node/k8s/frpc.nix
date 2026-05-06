{ config, ... }:
let
  namespace = "frpc";
  config-name = "frpc-config";
  token-secret-name = "frpc-token";
  tls-secret-name = "frpc-tls";
  tls-public-name = "public-tls";
  ingress = "192.168.88.90";
in
{
  sops = {
    secrets = {
      frpToken = { };
      frpCaCertB64 = { };
      frpClientCertB64 = { };
      frpClientKeyB64 = { };
    };
    templates = {
      frpc-token = {
        content = builtins.toJSON {
          apiVersion = "v1";
          kind = "Secret";
          metadata = {
            name = token-secret-name;
            namespace = namespace;
          };
          stringData = {
            value = config.sops.placeholder.frpToken;
          };
        };
        path = "/var/lib/rancher/k3s/server/manifests/frpc-token.json";
      };
      frpc-tls = {
        content = builtins.toJSON {
          apiVersion = "v1";
          kind = "Secret";
          metadata = {
            name = tls-secret-name;
            namespace = namespace;
          };
          data = {
            "token" = config.sops.placeholder.frpToken;
            "ca.pem" = config.sops.placeholder.frpCaCertB64;
            "clientCert.pem" = config.sops.placeholder.frpClientCertB64;
            "clientKey.pem" = config.sops.placeholder.frpClientKeyB64;
          };
        };
        path = "/var/lib/rancher/k3s/server/manifests/frpc-tls.json";
      };
    };
  };

  services.k3s.manifests = {
    frpc-namespace.content = {
      apiVersion = "v1";
      kind = "Namespace";
      metadata.name = namespace;
    };
    frpc-public-cert.content = {
      apiVersion = "cert-manager.io/v1";
      kind = "Certificate";
      metadata = {
        name = "frpc-public-cert";
        namespace = namespace;
      };
      spec = {
        secretName = tls-public-name;
        issuerRef = {
          kind = "ClusterIssuer";
          name = "letsencrypt";
        };
        usages = [
          "digital signature"
          "key encipherment"
        ];
        dnsNames = [
          "*.iverian.ru"
        ];
      };
    };
    frpc-config.content = {
      apiVersion = "v1";
      kind = "ConfigMap";
      metadata = {
        name = config-name;
        namespace = namespace;
      };
      data = {
        "frpc.toml" = ''
          clientId = "homelab"

          serverAddr = "external.lan"
          serverPort = 7000

          auth.method = "token"
          auth.tokenSource.type = "file"
          auth.tokenSource.file.path = "/token/value"

          transport.tls.enable = true
          transport.tls.certFile = "/tls/clientCert.pem"
          transport.tls.keyFile = "/tls/clientKey.pem"
          transport.tls.trustedCaFile = "/tls/ca.pem"
          transport.tls.serverName = "external.iverian.ru"

          [[proxies]]
          name = "auth01"
          type = "https"
          subdomain = "auth"
          [proxies.plugin]
          type = "https2https"
          localAddr = "auth.iverian.ru"
          crtPath = "/public-tls/tls.crt"
          keyPath = "/public-tls/tls.key"

          [[proxies]]
          name = "gitea01"
          type = "https"
          subdomain = "gitea"
          [proxies.plugin]
          type = "https2https"
          localAddr = "gitea.iverian.ru"
          crtPath = "/public-tls/tls.crt"
          keyPath = "/public-tls/tls.key"
        '';
      };
    };
    frpc-deployment.content = {
      apiVersion = "apps/v1";
      kind = "Deployment";
      metadata = {
        name = "frpc";
        namespace = namespace;
        labels = {
          "app.kubernetes.io/instance" = "frpc";
          "app.kubernetes.io/name" = "frpc";
        };
      };
      spec = {
        replicas = 1;
        strategy.type = "Recreate";
        selector.matchLabels = {
          "app.kubernetes.io/instance" = "frpc";
          "app.kubernetes.io/name" = "frpc";
        };
        template = {
          metadata = {
            annotations = {
              "reloader.stakater.com/auto" = "true";
            };
            labels = {
              "app.kubernetes.io/instance" = "frpc";
              "app.kubernetes.io/name" = "frpc";
            };
          };
          spec = {
            volumes = [
              {
                name = "config";
                configMap.name = config-name;
              }
              {
                name = "token";
                secret.secretName = token-secret-name;
              }
              {
                name = "tls";
                secret.secretName = tls-secret-name;
              }
              {
                name = "public-tls";
                secret.secretName = tls-public-name;
              }
            ];
            containers = [
              {
                name = "frpc";
                image = "snowdreamtech/frpc:0.68.1-trixie";
                command = [
                  "frpc"
                  "-c"
                  "/config/frpc.toml"
                ];
                resources = {
                  requests = {
                    cpu = "100m";
                    memory = "64Mi";
                  };
                  limits = {
                    cpu = "200m";
                    memory = "128Mi";
                  };
                };
                volumeMounts = [
                  {
                    name = "config";
                    mountPath = "/config";
                  }
                  {
                    name = "token";
                    mountPath = "/token";
                  }
                  {
                    name = "tls";
                    mountPath = "/tls";
                  }
                  {
                    name = "public-tls";
                    mountPath = "/public-tls";
                  }
                ];
              }
            ];
          };
        };
      };
    };
  };
}
