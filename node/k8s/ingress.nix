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
        ];
      };
    };
    envoy-gateway-private.content = {
      apiVersion = "gateway.networking.k8s.io/v1";
      kind = "Gateway";
      metadata = {
        name = "private";
        namespace = namespace;
        annotations."cert-manager.io/cluster-issuer" = "letsencrypt";
      };
      spec = {
        gatewayClassName = gateway-class;
        listeners = [
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
  };
}
