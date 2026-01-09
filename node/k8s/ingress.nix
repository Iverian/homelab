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
            port = 443;
            protocol = "HTTPS";
            tls = {
              mode = "Terminate";
              certificateRefs = [ { name = "eg-public-tls"; } ];
            };
          }
          {
            name = "private";
            hostname = "*.home.iverian.ru";
            port = 443;
            protocol = "HTTPS";
            tls = {
              mode = "Terminate";
              certificateRefs = [ { name = "eg-private-tls"; } ];
            };
          }
        ];
      };
    };
    envoy-gateway-block-private-route.content = {
      apiVersion = "gateway.networking.k8s.io/v1";
      kind = "HTTPRoute";
      metadata = {
        name = "block-private";
        namespace = namespace;
      };
      spec = {
        parentRefs = [
          {
            name = "main";
          }
        ];
        hostnames = [ "*.home.iverian.ru" ];
        rules = [
          {
            matches = [
              {
                headers = [
                  {
                    name = "X-Source";
                    value = "frp";
                  }
                ];
              }
            ];
            filters = [
              {
                type = "ExtensionRef";
                extensionRef = {
                  group = "gateway.envoyproxy.io";
                  kind = "HTTPRouteFilter";
                  name = "block-private-response";
                };
              }
            ];
          }
        ];
      };
    };
    envoy-gateway-block-private-response.content = {
      apiVersion = "gateway.envoyproxy.io/v1alpha1";
      kind = "HTTPRouteFilter";
      metadata = {
        name = "block-private-response";
        namespace = namespace;
      };
      spec = {
        directResponse = {
          contentType = "text/plain";
          statusCode = "404";
          body = {
            type = "Inline";
            inline = "not found";
          };
        };
      };
    };
  };
}
