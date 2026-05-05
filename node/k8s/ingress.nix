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
            allowedRoutes.namespaces.from = "All";
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
    envoy-gateway-http-redirect-public.content = {
      apiVersion = "gateway.networking.k8s.io/v1";
      kind = "HTTPRoute";
      metadata = {
        name = "http-to-https-redirect-public";
        namespace = namespace;
      };
      spec = {
        parentRefs = [
          {
            name = "main";
            namespace = namespace;
            sectionName = "public";
          }
        ];
        rules = [
          {
            matches = [
              {
                headers = [
                  {
                    name = "x-from-where";
                    value = "frp";
                  }
                ];
              }
            ];
            filters = [ ];
          }
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
