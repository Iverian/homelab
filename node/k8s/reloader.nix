{ config, ... }:
let
  namespace = "reloader";
in
{
  services.k3s.autoDeployCharts.reloader = {
    name = "reloader";
    repo = "https://stakater.github.io/stakater-charts";
    version = "2.2.7";
    hash = "sha256-4kHAP6OxRsyM62a8FvXHTAsdt6APyIqPLOC/GTJcXFw=";
    targetNamespace = namespace;
    createNamespace = true;
  };
}
