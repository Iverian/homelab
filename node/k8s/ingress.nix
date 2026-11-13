{ config, lib, ... }:
let
  namespace = "envoy-gateway-system";
  gateway-class = "eg";
in
{
  imports = [ ./trusted-ip.nix ];
  homelab.trustedIP.enforce = true;
  services.k3s.manifests = rec {
    envoy-gateway-namespace.content = {
      apiVersion = "v1";
      kind = "Namespace";
      metadata.name = namespace;
    };
    envoy-gateway-crds.source = ./manifest/envoy-gateway-crds.yaml;
    envoy-gateway.source = ./manifest/envoy-gateway.yaml;
    envoy-gateway-class.content = {
      apiVersion = "gateway.networking.k8s.io/v1";
      kind = "GatewayClass";
      metadata.name = gateway-class;
      spec.controllerName = "gateway.envoyproxy.io/gatewayclass-controller";
    };
    envoy-proxy-external.content = {
      apiVersion = "gateway.envoyproxy.io/v1alpha1";
      kind = "EnvoyProxy";
      metadata = {
        name = "external";
        namespace = namespace;
      };
      spec.provider = {
        type = "Kubernetes";
        kubernetes.envoyService = {
          name = "envoy-external";
          type = "ClusterIP";
        };
      };
    };
    envoy-gateway-external.content = {
      apiVersion = "gateway.networking.k8s.io/v1";
      kind = "Gateway";
      metadata = {
        name = "external";
        namespace = namespace;
      };
      spec = {
        gatewayClassName = gateway-class;
        infrastructure.parametersRef = {
          group = "gateway.envoyproxy.io";
          kind = "EnvoyProxy";
          name = "external";
        };
        listeners = [
          {
            name = "public";
            hostname = "*.iverian.ru";
            port = 8080;
            protocol = "HTTP";
          }
          {
            name = "public-secure";
            hostname = "*.iverian.ru";
            port = 8443;
            protocol = "HTTPS";
            allowedRoutes.namespaces.from = "All";
            tls = {
              mode = "Terminate";
              certificateRefs = [ { name = "eg-public-tls"; } ];
            };
          }
        ];
      };
    };
    envoy-gateway-policy-external.content = {
      apiVersion = "gateway.envoyproxy.io/v1alpha1";
      kind = "ClientTrafficPolicy";
      metadata = {
        name = "external-policy";
        namespace = namespace;
      };
      spec = {
        targetRefs = [
          {
            group = "gateway.networking.k8s.io";
            kind = "Gateway";
            name = "external";
          }
        ];
        enableProxyProtocol = true;
        proxyProtocol = {
          optional = false;
        };
      };
    };
    envoy-proxy-main.content = {
      apiVersion = "gateway.envoyproxy.io/v1alpha1";
      kind = "EnvoyProxy";
      metadata = {
        name = "main";
        namespace = namespace;
      };
      spec.provider = {
        type = "Kubernetes";
        kubernetes.envoyService = {
          loadBalancerIP = (builtins.head envoy-gateway-main.content.spec.addresses).value;
          annotations."metallb.io/address-pool" = "main";
        };
      };
    };
    envoy-gateway-main.content = {
      apiVersion = "gateway.networking.k8s.io/v1";
      kind = "Gateway";
      metadata = {
        name = "main";
        namespace = namespace;
      };
      spec = {
        gatewayClassName = gateway-class;
        infrastructure.parametersRef = {
          group = "gateway.envoyproxy.io";
          kind = "EnvoyProxy";
          name = "main";
        };
        addresses = [
          {
            type = "IPAddress";
            value = "192.168.90.90";
          }
        ];
        listeners = [
          {
            name = "http";
            port = 80;
            protocol = "HTTP";
          }
          {
            name = "https";
            port = 443;
            protocol = "HTTPS";
            allowedRoutes.namespaces.from = "All";
            tls = {
              mode = "Terminate";
              certificateRefs = [ { name = "eg-public-tls"; } ];
            };
          }
        ];
      };
    };
    envoy-gateway-public-certificate.content = {
      apiVersion = "cert-manager.io/v1";
      kind = "Certificate";
      metadata = {
        name = "eg-public-tls";
        namespace = namespace;
      };
      spec = {
        secretName = "eg-public-tls";
        dnsNames = [ "*.iverian.ru" ];
        issuerRef = {
          name = "letsencrypt";
          kind = "ClusterIssuer";
        };
      };
    };
    envoy-gateway-ratelimit-valkey.content = {
      apiVersion = "hyperspike.io/v1";
      kind = "Valkey";
      metadata = {
        name = "ratelimit";
        namespace = namespace;
      };
      spec = {
        nodes = 1;
        anonymousAuth = true;
        storage.spec = {
          accessModes = [ "ReadWriteOnce" ];
          storageClassName = "local-path";
          resources.requests.storage = "1Gi";
        };
      };
    };

    envoy-gateway-ratelimit-policy.content = {
      apiVersion = "gateway.envoyproxy.io/v1alpha1";
      kind = "BackendTrafficPolicy";
      metadata = {
        name = "external-ratelimit";
        namespace = namespace;
      };
      spec = {
        targetRefs = [
          (
            {
              group = "gateway.networking.k8s.io";
              kind = "Gateway";
              name = "external";
            }
            // lib.optionalAttrs config.homelab.trustedIP.enforce { sectionName = "public-secure"; }
          )
        ];
        rateLimit = {
          type = "Global";
          global.rules =
            if config.homelab.trustedIP.enforce then
              import ./trusted-ip-rules.nix
            else
              [
                {
                  clientSelectors = [
                    {
                      sourceCIDR = {
                        type = "Distinct";
                        value = "0.0.0.0/0";
                      };
                    }
                  ];
                  limit = {
                    requests = 100;
                    unit = "Minute";
                  };
                }
              ];
        };
      };
    };

    envoy-gateway-http-redirect.content = {
      apiVersion = "gateway.networking.k8s.io/v1";
      kind = "HTTPRoute";
      metadata = {
        name = "http-to-https-redirect";
        namespace = namespace;
      };
      spec = {
        parentRefs = [
          {
            name = "external";
            namespace = namespace;
            sectionName = "public";
          }
          {
            name = "main";
            namespace = namespace;
            sectionName = "http";
          }
        ];
        rules = [
          {
            filters = [
              {
                type = "RequestRedirect";
                requestRedirect = {
                  scheme = "https";
                  statusCode = 301;
                };
              }
            ];
          }
        ];
      };
    };
  };
}
