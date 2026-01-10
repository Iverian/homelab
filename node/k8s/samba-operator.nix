{ config, ... }:
let
  namespace = "samba-operator-system";
in
{
  services.k3s.manifests = {
    samba-operator.source = ./manifest/samba-operator.yaml;

  };
}
