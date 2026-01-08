{ config, ... }:
let
  namespace = "media";
in
{
  services.k3s.manifests = {
    media-namespace.content = {
      apiVersion = "v1";
      kind = "Namespace";
      metadata = {
        name = namespace;
      };
    };
    media-storage.content = {
      apiVersion = "v1";
      kind = "PersistentVolumeClaim";
      metadata = {
        name = "media";
        namespace = namespace;
      };
      spec = {
        resources.requests.storage = "2Ti";
        accessModes = [ "ReadWriteMany" ];
        persistentVolumeReclaimPolicy = "Retain";
      };
    };
  };
}
