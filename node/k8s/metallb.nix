{ config, ... }:
let
  namespace = "metallb";
in
{
  services.k3s.autoDeployCharts.metallb = {
    name = "metallb";
    repo = "https://metallb.github.io/metallb";
    version = "0.15.3";
    hash = "sha256-J9t2HFrSUl/RMMkv4vLUUA+IcOQC/v48nLjTTYpxpww=";
    targetNamespace = namespace;
    createNamespace = true;
  };
  services.k3s.manifests = {
    metallb-pool.content = {
      apiVersion = "metallb.io/v1beta1";
      kind = "IPAddressPool";
      metadata = {
        name = "main";
        namespace = namespace;
      };
      spec = {
        addresses = [ "192.168.88.90-192.168.88.100" ];
      };
    };
    metallb-advertisement.content = {
      apiVersion = "metallb.io/v1beta1";
      kind = "L2Advertisement";
      metadata = {
        name = "main";
        namespace = namespace;
      };
    };
  };
}
