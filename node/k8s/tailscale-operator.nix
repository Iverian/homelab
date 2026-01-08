{ config, ... }:
let
  namespace = "tailscale-operator";
in
{
  sops.secrets.tailscaleClientId = { };
  sops.secrets.tailscaleClientSecret = { };
  services.k3s.autoDeployCharts.tailscale-operator = {
    name = "tailscale-operator";
    repo = "https://pkgs.tailscale.com/helmcharts";
    version = "1.92.5";
    hash = "sha256-nV0Ql9Z+Fcf7oH5SwmcNieIVBIoD37N+jNhGnzp+K8A=";
    targetNamespace = namespace;
    createNamespace = true;
    values = {
      oauth = {
        clientId = config.sops.secrets.tailscaleClientId;
        clientSecret = config.sops.secrets.tailscaleClientSecret;
      };
    };
  };
  services.k3s.manifests = {
    # metallb-pool.content = {
    #   apiVersion = "metallb.io/v1beta1";
    #   kind = "IPAddressPool";
    #   metadata = {
    #     name = "main";
    #     namespace = namespace;
    #   };
    #   spec = {
    #     addresses = [ "192.168.88.90-192.168.88.100" ];
    #   };
    # };
    # metallb-advertisement.content = {
    #   apiVersion = "metallb.io/v1beta1";
    #   kind = "L2Advertisement";
    #   metadata = {
    #     name = "main";
    #     namespace = namespace;
    #   };
    # };
  };
}
