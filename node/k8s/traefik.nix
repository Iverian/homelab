{ config, ... }:
let
  namespace = "traefik";
in
{
  services.k3s.disable = [ "traefik" ];
  services.k3s.autoDeployCharts.traefik-external = {
    name = "traefik";
    repo = "https://traefik.github.io/charts";
    version = "38.0.2";
    hash = "sha256-J9t2HFrSUl/RMMkv4vLUUA+IcOQC/v48nLjTTYpxpww=";
    targetNamespace = namespace;
    createNamespace = true;
    values = {
      deployment = {
        podAnnotations = {
          "prometheus.io/port" = "8082";
          "prometheus.io/scrape" = "true";
        };
      };
      providers = {
        kubernetesIngress.publishedService.enabled = true;
        kubernetesCRD.allowCrossNamespace = true;
      };
    };
  };
}
