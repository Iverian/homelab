{ ... }:
let
  namespace = "rpg-cards";
in
{
  services.k3s.manifests = {
    rpg-cards-namespace.content = {
      apiVersion = "v1";
      kind = "Namespace";
      metadata.name = namespace;
    };

    rpg-cards-deployment.content = {
      apiVersion = "apps/v1";
      kind = "Deployment";
      metadata = {
        name = "rpg-cards";
        namespace = namespace;
        labels.app = "rpg-cards";
      };
      spec = {
        replicas = 1;
        selector.matchLabels.app = "rpg-cards";
        template = {
          metadata.labels.app = "rpg-cards";
          spec.containers = [
            {
              name = "rpg-cards";
              image = "gitea.iverian.ru/iverian/rpg-cards:1.0.1";
              ports = [
                {
                  name = "http";
                  containerPort = 8080;
                  protocol = "TCP";
                }
              ];
            }
          ];
        };
      };
    };

    rpg-cards-service.content = {
      apiVersion = "v1";
      kind = "Service";
      metadata = {
        name = "rpg-cards";
        namespace = namespace;
      };
      spec = {
        selector.app = "rpg-cards";
        ports = [
          {
            name = "http";
            port = 8080;
            targetPort = "http";
            protocol = "TCP";
          }
        ];
      };
    };

    rpg-cards-httproute.content = {
      apiVersion = "gateway.networking.k8s.io/v1";
      kind = "HTTPRoute";
      metadata = {
        name = "rpg-cards";
        namespace = namespace;
      };
      spec = {
        hostnames = [ "rpg-cards.iverian.ru" ];
        parentRefs = [
          {
            name = "main";
            namespace = "envoy-gateway-system";
          }
        ];
        rules = [
          {
            matches = [
              {
                path = {
                  type = "PathPrefix";
                  value = "/";
                };
              }
            ];
            backendRefs = [
              {
                name = "rpg-cards";
                port = 8080;
              }
            ];
          }
        ];
      };
    };
  };
}
