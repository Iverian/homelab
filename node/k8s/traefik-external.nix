{ config, ... }:
let
  namespace = "traefik-external";
in
{
  services.k3s.autoDeployCharts.traefik-external = {
    name = "traefik-external";
    repo = "https://traefik.github.io/charts";
    version = "38.0.2";
    hash = "sha256-J9t2HFrSUl/RMMkv4vLUUA+IcOQC/v48nLjTTYpxpww=";
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
