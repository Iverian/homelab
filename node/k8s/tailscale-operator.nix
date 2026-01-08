{ config, ... }:
let
  namespace = "tailscale-operator";
in
{
  sops = {
    secrets = {
      tailscaleClientId = { };
      tailscaleClientSecret = { };
    };
    templates.tailscale-operator-oauth = {
      content = builtins.toJSON {
        apiVersion = "v1";
        kind = "Secret";
        metadata = {
          name = "operator-oauth";
          namespace = namespace;
        };
        stringData = {
          client_id = config.sops.placeholder.tailscaleClientId;
          client_secret = config.sops.placeholder.tailscaleClientSecret;
        };
      };
      path = "/var/lib/rancher/k3s/server/manifests/tailscale-operator-oauth.json";
    };
  };
  services.k3s.autoDeployCharts.tailscale-operator = {
    name = "tailscale-operator";
    repo = "https://pkgs.tailscale.com/helmcharts";
    version = "1.92.5";
    hash = "sha256-nV0Ql9Z+Fcf7oH5SwmcNieIVBIoD37N+jNhGnzp+K8A=";
    targetNamespace = namespace;
    createNamespace = true;
  };
  services.k3s.manifests = {
    tailscale-subnet-router.content = {
      apiVersion = "tailscale.com/v1alpha1";
      kind = "Connector";
      metadata = {
        name = "subnet-router";
        namespace = namespace;
      };
      spec = {
        replicas = 1;
        exitNode = true;
        subnetRouter = {
          advertiseRoutes = [ "192.168.88.128/25" ];
        };
      };
    };
  };
}
