{ config, ... }:
let
  namespace = "kube-system";
in
{
  services.k3s.manifests = {
    media-namespace.content = {
      apiVersion = "traefik.io/v1alpha1";
      kind = "Middleware";
      metadata = {
        name = "redirect";
        namespace = namespace;
      };
      spec = {
        redirectScheme = {
          scheme = "https";
          permanent = true;
        };
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
