{ config, ... }:
let
  namespace = "postgres-operator";
in
{
  services.k3s.autoDeployCharts.postgres-operator = {
    name = "postgres-operator";
    repo = "https://opensource.zalando.com/postgres-operator/charts/postgres-operator";
    version = "1.15.1";
    hash = "sha256-J9t2HFrSUl/RMMkv4vLUUA+IcOQC/v48nLjTTYpxpww=";
    targetNamespace = namespace;
    createNamespace = true;
    values = {
      enableJsonLogging = true;
    };
  };
}
