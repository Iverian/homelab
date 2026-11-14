{ ... }:
let
  namespace = "dns-proxy";
  name = "dns-proxy";
  labels.app = name;
  updaterPath = ../../services/dns-blocklist-updater;
  updaterManifest = builtins.fromJSON (builtins.readFile (updaterPath + "/manifest.json"));
  updaterHash = builtins.substring 0 20 (
    builtins.hashString "sha256" (
      builtins.concatStringsSep "" (
        map (file: builtins.readFile (updaterPath + "/${file}")) (
          [ "Dockerfile" ] ++ updaterManifest.hashFiles
        )
      )
    )
  );
  updaterImage = "${updaterManifest.image}:${updaterHash}";
  blocklistUrl = "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/wildcard/light-onlydomains.txt";
  blocklistFile = "/var/lib/dnscrypt-proxy/blocked-names.txt";
  queryLogFile = "${blocklistFile}.query.log";
  resolverListKey = "RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3";
  config = ''
    listen_addresses = [':5353']
    max_clients = 250

    server_names = ['odoh-cloudflare', 'odoh-crypto-sx']

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

    cache = true
    cache_size = 4096
    cache_min_ttl = 60
    cache_max_ttl = 86400
    cache_neg_min_ttl = 60
    cache_neg_max_ttl = 600

    enable_hot_reload = true

    bootstrap_resolvers = []
    ignore_system_dns = false
    netprobe_timeout = 0

    block_ipv6 = false
    block_unqualified = false
    block_undelegated = false

    log_level = 2
    use_syslog = false
    log_files_max_size = 0

    [query_log]
    file = '${queryLogFile}'
    format = 'ltsv'
    ignored_qtypes = ['DNSCRYPT-SIGNED']

    [blocked_names]
    blocked_names_file = '${blocklistFile}'

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
      { server_name = '*', via = ['odohrelay-crypto-sx'] }
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

    dns-proxy-mtail.content = {
      apiVersion = "v1";
      kind = "ConfigMap";
      metadata = {
        name = "dns-proxy-mtail";
        inherit namespace;
      };
      data."dnscrypt.mtail" = ''
        counter queries_total
        counter queries by host, type, return, cached, server
        histogram queries_duration_ms buckets 1, 2, 4, 8, 16, 32, 64, 128, 256 by return, server, type

        /^time:[0-9]+[[:space:]]+host:(?P<host>[^[:space:]]+)[[:space:]]+message:(?P<message>[^[:space:]]+)[[:space:]]+type:(?P<type>[^[:space:]]+)[[:space:]]+return:(?P<return>[^[:space:]]+)[[:space:]]+cached:(?P<cached>[0-1])[[:space:]]+duration:(?P<duration>[0-9]+)[[:space:]]+server:(?P<server>[^[:space:]]+)$/ {
          queries_total++
          queries[$host][$type][$return][$cached][$server]++
          $cached == 0 {
            queries_duration_ms[$return][$server][$type] = $duration
          }
        }
      '';
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
            annotations = {
              "checksum/config" = builtins.hashString "sha256" config;
              "configmap.reloader.stakater.com/reload" = "dns-proxy,dns-proxy-mtail";
              "prometheus.io/scrape" = "true";
              "prometheus.io/port" = "3903";
            };
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
            initContainers = [
              {
                name = "blocklist-bootstrap";
                image = updaterImage;
                imagePullPolicy = "Never";
                command = [ "/bin/sh" ];
                args = [
                  "-c"
                  ''
                    if ! python /app/update.py --url "$1" --output "$2"; then
                      if [ ! -f "$2" ]; then
                        echo "Initial blocklist download failed; starting with an empty blocklist" >&2
                        : > "$2"
                      fi
                    fi
                    touch "$3"
                  ''
                  "blocklist-bootstrap"
                  blocklistUrl
                  blocklistFile
                  queryLogFile
                ];
                resources = {
                  requests = {
                    cpu = "10m";
                    memory = "16Mi";
                  };
                  limits.memory = "64Mi";
                };
                securityContext = {
                  allowPrivilegeEscalation = false;
                  readOnlyRootFilesystem = true;
                  capabilities.drop = [ "ALL" ];
                };
                volumeMounts = [
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
                    mountPath = "/etc/dnscrypt-proxy/dnscrypt-proxy.toml";
                    subPath = "dnscrypt-proxy.toml";
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
              {
                name = "mtail";
                image = "ghcr.io/google/mtail:3.0.8@sha256:00ccb287115314f8fcbf002de0bfa991d8d76d192fff6e4422b7c69e8793087e";
                args = [
                  "--progs=/etc/mtail"
                  "--logs=${queryLogFile}"
                  "--address=0.0.0.0"
                  "--port=3903"
                ];
                ports = [
                  {
                    name = "metrics";
                    containerPort = 3903;
                  }
                ];
                resources = {
                  requests = {
                    cpu = "10m";
                    memory = "16Mi";
                  };
                  limits = {
                    cpu = "100m";
                    memory = "64Mi";
                  };
                };
                securityContext = {
                  allowPrivilegeEscalation = false;
                  readOnlyRootFilesystem = true;
                  capabilities.drop = [ "ALL" ];
                };
                volumeMounts = [
                  {
                    name = "resolver-lists";
                    mountPath = "/var/lib/dnscrypt-proxy";
                    readOnly = true;
                  }
                  {
                    name = "mtail";
                    mountPath = "/etc/mtail";
                    readOnly = true;
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
              {
                name = "mtail";
                configMap.name = "dns-proxy-mtail";
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

    dns-proxy-blocklist-update.content = {
      apiVersion = "batch/v1";
      kind = "CronJob";
      metadata = {
        name = "dns-blocklist-update";
        inherit namespace;
      };
      spec = {
        schedule = "17 3 * * *";
        concurrencyPolicy = "Forbid";
        startingDeadlineSeconds = 7200;
        successfulJobsHistoryLimit = 3;
        failedJobsHistoryLimit = 3;
        jobTemplate.spec = {
          backoffLimit = 3;
          activeDeadlineSeconds = 600;
          template.spec = {
            restartPolicy = "OnFailure";
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
                name = "update";
                image = updaterImage;
                imagePullPolicy = "Never";
                args = [
                  "--url"
                  blocklistUrl
                  "--output"
                  blocklistFile
                ];
                resources = {
                  requests = {
                    cpu = "10m";
                    memory = "16Mi";
                  };
                  limits.memory = "64Mi";
                };
                securityContext = {
                  allowPrivilegeEscalation = false;
                  readOnlyRootFilesystem = true;
                  capabilities.drop = [ "ALL" ];
                };
                volumeMounts = [
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
  };
}
