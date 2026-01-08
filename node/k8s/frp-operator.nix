{ config, ... }:
let
  namespace = "frp-operator";
in
{
  services.k3s.autoDeployCharts.frp-operator = {
    name = "frp-operator";
    repo = "https://zufardhiyaulhaq.com/frp-operator/charts/releases/";
    version = "1.4.0";
    hash = "sha256-J9t2HFrSUl/RMMkv4vLUUA+IcOQC/v48nLjTTYpxpww=";
    targetNamespace = namespace;
    createNamespace = true;
  };
}
