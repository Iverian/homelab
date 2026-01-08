{ config, ... }:
let
  namespace = "traefik-external";
in
{
  services.k3s.autoDeployCharts.traefik-external = {
    name = "traefik";
    repo = "https://traefik.github.io/charts";
    version = "38.0.2";
    hash = "sha256-mjMHob26QA6MbwYngHQho8/BgXZ+lXv9/EtEe98YpgM=";
    targetNamespace = namespace;
    createNamespace = true;
    values = {
      ingressClass = {
        enabled = true;
        isDefaultClass = false;
        name = "traefik-external";
      };
    };
  };
}
