{ ... }:
let
  namespace = "dns-proxy";
  name = "dns-proxy";
  labels.app = name;
  resolverListKey = "RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3";
  config = ''
    listen_addresses = [':5353']
    max_clients = 250

    ipv4_servers = true
    ipv6_servers = false
    dnscrypt_servers = false
    doh_servers = true
    odoh_servers = true
    require_dnssec = true
    require_nolog = true
    require_nofilter = true

    timeout = 5000
    keepalive = 30
    http3 = true
    http3_probe = false

    lb_strategy = 'wp2'
    lb_estimator = true

    cache = false

    bootstrap_resolvers = []
    ignore_system_dns = false
    netprobe_timeout = 0

    block_ipv6 = false
    block_unqualified = false
    block_undelegated = false

    log_level = 2
    use_syslog = false
    log_files_max_size = 0

    [sources.public-resolvers]
    urls = [
      'https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/public-resolvers.md',
      'https://download.dnscrypt.info/resolvers-list/v3/public-resolvers.md',
      'https://cdn.jsdelivr.net/gh/DNSCrypt/dnscrypt-resolvers@master/v3/public-resolvers.md'
    ]
    cache_file = '/var/lib/dnscrypt-proxy/public-resolvers.md'
    minisign_key = '${resolverListKey}'
    refresh_delay = 73
    cache_ttl = 168

    [sources.odoh-servers]
    urls = [
      'https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/odoh-servers.md',
      'https://download.dnscrypt.info/resolvers-list/v3/odoh-servers.md',
      'https://cdn.jsdelivr.net/gh/DNSCrypt/dnscrypt-resolvers@master/v3/odoh-servers.md'
    ]
    cache_file = '/var/lib/dnscrypt-proxy/odoh-servers.md'
    minisign_key = '${resolverListKey}'
    refresh_delay = 73
    cache_ttl = 168

    [sources.odoh-relays]
    urls = [
      'https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/odoh-relays.md',
      'https://download.dnscrypt.info/resolvers-list/v3/odoh-relays.md',
      'https://cdn.jsdelivr.net/gh/DNSCrypt/dnscrypt-resolvers@master/v3/odoh-relays.md'
    ]
    cache_file = '/var/lib/dnscrypt-proxy/odoh-relays.md'
    minisign_key = '${resolverListKey}'
    refresh_delay = 73
    cache_ttl = 168

    [anonymized_dns]
    routes = [
      { server_name = '*', via = ['*'] }
    ]
    skip_incompatible = false
  '';
in
{
  services.k3s.manifests = {
    dns-proxy-namespace.content = {
      apiVersion = "v1";
      kind = "Namespace";
      metadata.name = namespace;
    };

    dns-proxy-config.content = {
      apiVersion = "v1";
      kind = "ConfigMap";
      metadata = { inherit name namespace; };
      data."dnscrypt-proxy.toml" = config;
    };

    dns-proxy-cache.content = {
      apiVersion = "v1";
      kind = "PersistentVolumeClaim";
      metadata = { inherit name namespace; };
      spec = {
        accessModes = [ "ReadWriteOnce" ];
        storageClassName = "local-path";
        resources.requests.storage = "128Mi";
      };
    };

    dns-proxy-deployment.content = {
      apiVersion = "apps/v1";
      kind = "Deployment";
      metadata = { inherit name namespace; };
      spec = {
        replicas = 1;
        strategy.type = "Recreate";
        selector.matchLabels = labels;
        template = {
          metadata = {
            inherit labels;
            annotations."checksum/config" = builtins.hashString "sha256" config;
          };
          spec = {
            automountServiceAccountToken = false;
            securityContext = {
              runAsNonRoot = true;
              runAsUser = 65532;
              runAsGroup = 65532;
              fsGroup = 65532;
              seccompProfile.type = "RuntimeDefault";
            };
            containers = [
              {
                inherit name;
                image = "ghcr.io/klutchell/dnscrypt-proxy:2.1.20@sha256:9d4e4c1408f71f669ffdc34836d801442dddd7c176838c6d129938d2c1bd95b1";
                args = [
                  "-config"
                  "/etc/dnscrypt-proxy/dnscrypt-proxy.toml"
                ];
                ports = [
                  {
                    name = "dns-udp";
                    containerPort = 5353;
                    protocol = "UDP";
                  }
                  {
                    name = "dns-tcp";
                    containerPort = 5353;
                    protocol = "TCP";
                  }
                ];
                resources = {
                  requests = {
                    cpu = "20m";
                    memory = "32Mi";
                  };
                  limits.memory = "128Mi";
                };
                securityContext = {
                  allowPrivilegeEscalation = false;
                  readOnlyRootFilesystem = true;
                  capabilities.drop = [ "ALL" ];
                };
                readinessProbe = {
                  tcpSocket.port = "dns-tcp";
                  initialDelaySeconds = 5;
                  periodSeconds = 5;
                  timeoutSeconds = 2;
                  failureThreshold = 6;
                };
                livenessProbe = {
                  tcpSocket.port = "dns-tcp";
                  initialDelaySeconds = 30;
                  periodSeconds = 10;
                  timeoutSeconds = 2;
                  failureThreshold = 3;
                };
                volumeMounts = [
                  {
                    name = "config";
                    mountPath = "/etc/dnscrypt-proxy";
                    readOnly = true;
                  }
                  {
                    name = "resolver-lists";
                    mountPath = "/var/lib/dnscrypt-proxy";
                  }
                  {
                    name = "tmp";
                    mountPath = "/tmp";
                  }
                ];
              }
            ];
            volumes = [
              {
                name = "config";
                configMap.name = name;
              }
              {
                name = "resolver-lists";
                persistentVolumeClaim.claimName = name;
              }
              {
                name = "tmp";
                emptyDir = { };
              }
            ];
          };
        };
      };
    };

    dns-proxy-service.content = {
      apiVersion = "v1";
      kind = "Service";
      metadata = {
        inherit name namespace;
        annotations."metallb.io/address-pool" = "main";
      };
      spec = {
        selector = labels;
        type = "LoadBalancer";
        externalTrafficPolicy = "Local";
        ports = [
          {
            name = "dns-udp";
            port = 53;
            targetPort = "dns-udp";
            protocol = "UDP";
          }
          {
            name = "dns-tcp";
            port = 53;
            targetPort = "dns-tcp";
            protocol = "TCP";
          }
        ];
      };
    };
  };
}
