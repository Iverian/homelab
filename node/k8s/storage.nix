{ config, ... }:
let
  namespace = "kube-system";
in
{
  services.k3s.manifests = {
    storageclass-config.content = {
      apiVersion = "v1";
      kind = "ConfigMap";
      metadata = {
        name = "local-path-config";
        namespace = namespace;
      };
      data = {
        "config.json" = ''
          {
            "storageClassConfigs": {
              "storage": {
                "sharedFilesystemPath": "/data/hdd"
              },
              "local-path": {
                "sharedFilesystemPath": "/data/ssd"
              }
            }
          }
        '';
        "helperPod.yaml" = ''
          apiVersion: v1
          kind: Pod
          metadata:
            name: helper-pod
          spec:
            containers:
            - name: helper-pod
              image: "rancher/mirrored-library-busybox:1.36.1"
              imagePullPolicy: IfNotPresent
        '';
        setup = ''
          #!/bin/sh
          set -eu
          mkdir -m 0777 -p "''${VOL_DIR}"
          chmod 700 "''${VOL_DIR}/.."
        '';
        teardown = ''
          #!/bin/sh
          set -eu
          rm -rf "''${VOL_DIR}"
        '';
      };
    };
    storageclass-storage.content = {
      apiVersion = "storage.k8s.io/v1";
      kind = "StorageClass";
      metadata = {
        name = "storage";
        namespace = namespace;
      };
      provisioner = "rancher.io/local-path";
      reclaimPolicy = "Delete";
      volumeBindingMode = "WaitForFirstConsumer";
    };
    storageclass-default.content = {
      apiVersion = "storage.k8s.io/v1";
      kind = "StorageClass";
      metadata = {
        name = "local-path";
        namespace = namespace;
        annotations = {
          "storageclass.kubernetes.io/is-default-class" = "true";
        };
      };
      provisioner = "rancher.io/local-path";
      reclaimPolicy = "Delete";
      volumeBindingMode = "WaitForFirstConsumer";
    };
    storage-media.content = {
      apiVersion = "v1";
      kind = "PersistentVolume";
      metadata.name = "media";
      spec = {
        capacity.storage = "2Ti";
        accessModes = [ "ReadWriteMany" ];
        persistentVolumeReclaimPolicy = "Retain";
        hostPath.path = "/data/hdd/media";
      };
    };
  };
}
