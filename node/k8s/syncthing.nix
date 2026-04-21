{ config, ... }:
let
  namespace = "syncthing";
in
{
  services.k3s.autoDeployCharts.syncthing = {
    name = "syncthing";
    repo = "https://k8s-home-lab.github.io/helm-charts/";
    version = "4.0.0";
    hash = "sha256-O9uXdSBGuyoqUA5DbOtGyRzY0SEfHFmCyFcFmVq5jPg=";
    targetNamespace = namespace;
    createNamespace = true;
    values = {
      image = {
        repository = "syncthing/syncthing";
        tag = "2.0.13";
      };
      service = {
        main.ports.http.port = 8384;
        listen = {
          enabled = true;
          type = "NodePort";
          externalTrafficPolicy = "Local";
          ports.listen = {
            enabled = true;
            nodePort = 31070;
            port = 22000;
            protocol = "TCP";
            targetPort = 22000;
          };
        };
        listen-udp = {
          enabled = true;
          type = "NodePort";
          externalTrafficPolicy = "Local";
          ports.listen-udp = {
            enabled = true;
            nodePort = 31080;
            port = 22000;
            protocol = "UDP";
            targetPort = 22000;
          };
        };
        discovery = {
          enabled = true;
          type = "NodePort";
          externalTrafficPolicy = "Local";
          ports.discovery = {
            enabled = true;
            nodePort = 31090;
            port = 21027;
            protocol = "UDP";
            targetPort = 21027;
          };
        };
      };
      persistence.data = {
        enabled = "true";
        mountPath = "/var/syncthing";
        type = "pvc";
        storageClass = "storage";
        accessMode = "ReadWriteOnce";
        size = "1Gi";
      };
    };
  };
  services.k3s.manifests = {
    syncthing-httproute.content = {
      apiVersion = "gateway.networking.k8s.io/v1";
      kind = "HTTPRoute";
      metadata = {
        name = "syncthing";
        namespace = namespace;
      };
      spec = {
        hostnames = [ "syncthing.home.iverian.ru" ];
        parentRefs = [
          {
            group = "gateway.networking.k8s.io";
            kind = "Gateway";
            name = "main";
            namespace = "envoy-gateway-system";
          }
        ];
        rules = [
          {
            backendRefs = [
              {
                group = "";
                kind = "Service";
                name = "syncthing";
                port = 8384;
              }
            ];
            matches = [
              {
                path = {
                  type = "PathPrefix";
                  value = "/";
                };
              }
            ];
          }
        ];
      };
    };
  };
}
