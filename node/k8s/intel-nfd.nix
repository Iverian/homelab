{ config, ... }:
{
  services.k3s.manifests = {
    intel-nfd.source = ./manifest/intel-nfd.yaml;
    intel-node-feature-rules.source = ./manifest/intel-node-feature-rules.yaml;
    intel-nfd-labeled-nodes.source = ./manifest/intel-nfd-labeled-nodes.yaml;
  };
}
