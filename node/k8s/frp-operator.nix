{ config, ... }:
let
  namespace = "frp-operator";
in
{
  services.k3s.autoDeployCharts.frp-operator = {
    name = "frp-operator";
    repo = "https://zufardhiyaulhaq.com/frp-operator/charts/releases/";
    version = "1.4.0";
    hash = "sha256-A2GBAl2G6HHjbMlFsYAMbwHs4JYY3CMhofg/Eoc0TAQ=";
    targetNamespace = namespace;
    createNamespace = true;
  };
}
