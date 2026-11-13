{ config, lib, ... }:
let
  namespace = "envoy-gateway-system";
  name = "trusted-ip";
  servicePath = ../../services/trusted-ip;
  imageManifest = builtins.fromJSON (builtins.readFile (servicePath + "/manifest.json"));
  source = builtins.readFile ../../services/trusted-ip/server.py;
  imageHash = builtins.substring 0 20 (
    builtins.hashString "sha256" (
      builtins.concatStringsSep "" (
        map (file: builtins.readFile (servicePath + "/${file}")) (
          [ "Dockerfile" ] ++ imageManifest.hashFiles
        )
      )
    )
  );
  labels.app = name;
  manifest = kind: spec: {
    apiVersion = if kind == "Deployment" then "apps/v1" else "v1";
    inherit kind spec;
    metadata = { inherit name namespace; };
  };
in
{
  options.homelab.trustedIP.enforce = lib.mkEnableOption "trusted-IP classification on external HTTPS traffic";

  config.services.k3s.manifests = {
    trusted-ip-code.content = {
      apiVersion = "v1";
      kind = "ConfigMap";
      metadata = {
        name = "trusted-ip-code";
        inherit namespace;
      };
      data."server.py" = source;
    };
    trusted-ip-valkey.content = {
      apiVersion = "hyperspike.io/v1";
      kind = "Valkey";
      metadata = {
        name = "trusted-ip-store";
        inherit namespace;
      };
      spec = {
        nodes = 1;
        anonymousAuth = true;
        storage.spec = {
          accessModes = [ "ReadWriteOnce" ];
          storageClassName = "local-path";
          resources.requests.storage = "1Gi";
        };
      };
    };
    trusted-ip-service.content = manifest "Service" {
      selector = labels;
      ports = [
        {
          name = "grpc";
          port = 9001;
          targetPort = 9001;
          appProtocol = "kubernetes.io/h2c";
        }
      ];
    };
    trusted-ip-deployment.content = manifest "Deployment" {
      replicas = 2;
      selector.matchLabels = labels;
      strategy = {
        type = "RollingUpdate";
        rollingUpdate = {
          maxUnavailable = 0;
          maxSurge = 1;
        };
      };
      template = {
        metadata = {
          inherit labels;
          annotations."checksum/code" = builtins.hashString "sha256" source;
          annotations."prometheus.io/scrape" = "true";
          annotations."prometheus.io/port" = "9090";
        };
        spec = {
          automountServiceAccountToken = false;
          terminationGracePeriodSeconds = 15;
          securityContext = {
            runAsNonRoot = true;
            runAsUser = 65532;
            runAsGroup = 65532;
            seccompProfile.type = "RuntimeDefault";
          };
          containers = [
            {
              inherit name;
              image = "${imageManifest.image}:${imageHash}";
              imagePullPolicy = "Never";
              ports = [
                {
                  name = "grpc";
                  containerPort = 9001;
                }
                {
                  name = "metrics";
                  containerPort = 9090;
                }
              ];
              env = [
                {
                  name = "REDIS_URL";
                  value = "redis://trusted-ip-store:6379/0";
                }
                {
                  name = "AUTH_HOST";
                  value = "auth.iverian.ru";
                }
                {
                  name = "AUTHELIA_AUTHZ_URL";
                  value = "http://authelia.authelia.svc.cluster.local/api/authz/trusted-ip";
                }
              ];
              resources = {
                requests = {
                  cpu = "50m";
                  memory = "96Mi";
                };
                limits.memory = "256Mi";
              };
              securityContext = {
                allowPrivilegeEscalation = false;
                readOnlyRootFilesystem = true;
                capabilities.drop = [ "ALL" ];
              };
              readinessProbe = {
                grpc.port = 9001;
                initialDelaySeconds = 2;
                periodSeconds = 5;
                timeoutSeconds = 2;
              };
              livenessProbe = {
                grpc.port = 9001;
                initialDelaySeconds = 10;
                periodSeconds = 10;
                timeoutSeconds = 2;
              };
              volumeMounts = [
                {
                  name = "code";
                  mountPath = "/app";
                  readOnly = true;
                }
              ];
            }
          ];
          volumes = [
            {
              name = "code";
              configMap.name = "trusted-ip-code";
            }
          ];
        };
      };
    };
    trusted-ip-network.content = {
      apiVersion = "networking.k8s.io/v1";
      kind = "NetworkPolicy";
      metadata = { inherit name namespace; };
      spec = {
        podSelector.matchLabels = labels;
        policyTypes = [
          "Ingress"
          "Egress"
        ];
        ingress = [
          {
            from = [ { podSelector.matchLabels."gateway.envoyproxy.io/owning-gateway-name" = "external"; } ];
            ports = [
              {
                port = 9001;
                protocol = "TCP";
              }
            ];
          }
          {
            from = [ { namespaceSelector.matchLabels."kubernetes.io/metadata.name" = "monitoring"; } ];
            ports = [
              {
                port = 9090;
                protocol = "TCP";
              }
            ];
          }
        ];
        egress = [
          {
            to = [
              {
                namespaceSelector.matchLabels."kubernetes.io/metadata.name" = "kube-system";
                podSelector.matchLabels."k8s-app" = "kube-dns";
              }
            ];
            ports = [
              {
                port = 53;
                protocol = "UDP";
              }
              {
                port = 53;
                protocol = "TCP";
              }
            ];
          }
          {
            to = [ { podSelector.matchLabels."app.kubernetes.io/instance" = "trusted-ip-store"; } ];
            ports = [
              {
                port = 6379;
                protocol = "TCP";
              }
            ];
          }
          {
            to = [
              {
                namespaceSelector.matchLabels."kubernetes.io/metadata.name" = "authelia";
                podSelector.matchLabels."app.kubernetes.io/name" = "authelia";
              }
            ];
            ports = [
              {
                port = 9091;
                protocol = "TCP";
              }
            ];
          }
        ];
      };
    };
    trusted-ip-store-network.content = {
      apiVersion = "networking.k8s.io/v1";
      kind = "NetworkPolicy";
      metadata = {
        name = "trusted-ip-store";
        inherit namespace;
      };
      spec = {
        podSelector.matchLabels."app.kubernetes.io/instance" = "trusted-ip-store";
        policyTypes = [ "Ingress" ];
        ingress = [
          {
            from = [
              { podSelector.matchLabels = labels; }
              { namespaceSelector.matchLabels."kubernetes.io/metadata.name" = "valkey-operator-system"; }
            ];
            ports = [
              {
                port = 6379;
                protocol = "TCP";
              }
            ];
          }
        ];
      };
    };
  }
  // lib.optionalAttrs config.homelab.trustedIP.enforce {
    trusted-ip-security.content = {
      apiVersion = "gateway.envoyproxy.io/v1alpha1";
      kind = "SecurityPolicy";
      metadata = { inherit name namespace; };
      spec = {
        targetRefs = [
          {
            group = "gateway.networking.k8s.io";
            kind = "Gateway";
            name = "external";
            sectionName = "public-secure";
          }
        ];
        extAuth = {
          failOpen = false;
          timeout = "2s";
          grpc.backendRefs = [
            {
              name = name;
              port = 9001;
            }
          ];
        };
      };
    };
  };
}
