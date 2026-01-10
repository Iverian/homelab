{ config, ... }:
let
  namespace = "netdata";
in
{
  services.k3s.autoDeployCharts.netdata = {
    name = "netdata";
    repo = "https://netdata.github.io/helmchart";
    version = "3.7.157";
    hash = "sha256-W9oJhzOO2HNQ/6n0pglWc2rwdGadQpys3HrdJzVFjIg=";
    targetNamespace = namespace;
    createNamespace = true;
    values = {
      parent.env.NETDATA_DISABLE_CLOUD = 1;
      child.env.NETDATA_DISABLE_CLOUD = 1;
      k8sState.env.NETDATA_DISABLE_CLOUD = 1;
    };
  };
  services.k3s.manifests.netdata-httproute.content = {
    apiVersion = "gateway.networking.k8s.io/v1";
    kind = "HTTPRoute";
    metadata = {
      name = "netdata";
      namespace = namespace;
    };
    spec = {
      hostnames = [ "netdata.home.iverian.ru" ];
      parentRefs = [
        {
          group = "gateway.networking.k8s.io";
          kind = "Gateway";
          name = "main";
          namespace = "envoy-gateway-system";
        }
      ];
      rules = [
        {
          backendRefs = [
            {
              group = "";
              kind = "Service";
              name = "netdata";
              port = 19999;
            }
          ];
          matches = [
            {
              path = {
                type = "PathPrefix";
                value = "/";
              };
            }
          ];
        }
      ];
    };
  };
}
