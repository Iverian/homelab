{ config, ... }:
let
  namespace = "envoy-gateway-system";
  gateway-class = "eg";
in
{
  services.k3s.disable = [ "traefik" ];
  services.k3s.manifests = {
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
    envoy-gateway-public.content = {
      apiVersion = "gateway.networking.k8s.io/v1";
      kind = "Gateway";
      metadata = {
        name = "public";
        namespace = namespace;
        annotations."cert-manager.io/cluster-issuer" = "letsencrypt";
      };
      spec = {
        gatewayClassName = gateway-class;
        addresses = [
          {
            type = "IPAddress";
            value = "192.168.88.92";
          }
        ];
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
    envoy-gateway-policy-public.content = {
      apiVersion = "gateway.envoyproxy.io/v1alpha1";
      kind = "ClientTrafficPolicy";
      metadata = {
        name = "public-policy";
        namespace = namespace;
      };
      spec = {
        targetRefs = [
          {
            group = "gateway.networking.k8s.io";
            kind = "Gateway";
            name = "public";
          }
        ];
        enableProxyProtocol = true;
        proxyProtocol = {
          optional = false;
        };
      };
    };
    # envoy-gateway-backend-policy-public.content = {
    #   apiVersion = "gateway.envoyproxy.io/v1alpha1";
    #   kind = "BackendTrafficPolicy";
    #   metadata = {
    #     name = "public-backend-policy";
    #     namespace = namespace;
    #   };
    #   spec = {
    #     targetRefs = [
    #       {
    #         group = "gateway.networking.k8s.io";
    #         kind = "Gateway";
    #         name = "public";
    #       }
    #     ];
    #     rateLimit.global.rules = [
    #       {
    #         clientSelectors = [
    #           {
    #             sourceCIDR = {
    #               type = "Distinct";
    #               value = "0.0.0.0/0";
    #             };
    #           }
    #         ];
    #         limit = {
    #           requests = 5;
    #           unit = "Second";
    #         };
    #         shared = true;
    #       }
    #     ];
    #   };
    # };
    envoy-gateway-main.content = {
      apiVersion = "gateway.networking.k8s.io/v1";
      kind = "Gateway";
      metadata = {
        name = "main";
        namespace = namespace;
        annotations."cert-manager.io/cluster-issuer" = "letsencrypt";
      };
      spec = {
        gatewayClassName = gateway-class;
        addresses = [
          {
            type = "IPAddress";
            value = "192.168.88.90";
          }
        ];
        listeners = [
          {
            name = "public";
            hostname = "*.iverian.ru";
            port = 80;
            protocol = "HTTP";
          }
          {
            name = "public-secure";
            hostname = "*.iverian.ru";
            port = 443;
            protocol = "HTTPS";
            allowedRoutes.namespaces.from = "All";
            tls = {
              mode = "Terminate";
              certificateRefs = [ { name = "eg-public-tls"; } ];
            };
          }
          {
            name = "private";
            hostname = "*.home.iverian.ru";
            port = 80;
            protocol = "HTTP";
          }
          {
            name = "private-secure";
            hostname = "*.home.iverian.ru";
            port = 443;
            protocol = "HTTPS";
            allowedRoutes.namespaces.from = "All";
            tls = {
              mode = "Terminate";
              certificateRefs = [ { name = "eg-private-tls"; } ];
            };
          }
        ];
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
            name = "public";
            namespace = namespace;
            sectionName = "public";
          }
          {
            name = "main";
            namespace = namespace;
            sectionName = "public";
          }
          {
            name = "main";
            namespace = namespace;
            sectionName = "private";
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
