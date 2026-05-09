{ ... }:
let
  namespace = "valkey-operator-system";
in
{
  services.k3s.autoDeployCharts.valkey-operator = {
    name = "valkey-operator";
    repo = "oci://ghcr.io/hyperspike/valkey-operator";
    version = "v0.0.61-chart";
    hash = "sha256-Q4PDvbuZ4IGxH3RYArLsNcBuyiq+WzOp5r1M/pfJmNQ=";
    targetNamespace = namespace;
    createNamespace = true;
    values = { };
  };
}
