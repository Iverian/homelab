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
      parent.env.DO_NOT_TRACK = 1;
      child.env.DO_NOT_TRACK = 1;
      k8sState.env.DO_NOT_TRACK = 1;
    };
  };
}
