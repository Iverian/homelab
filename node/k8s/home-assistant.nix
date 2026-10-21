{ config, ... }:
let
  namespace = "home-assistant";
  zigbee-device = "/dev/serial/by-id/usb-1a86_USB_Serial-if00-port0";
  zha-entry-id = "01KSR5BZHA000000000000000";
  oidc-auth-version = "1.1.0";
  oidc-auth-source = "https://github.com/christiaangoossens/hass-oidc-auth/archive/refs/tags/v${oidc-auth-version}.zip";
  oidc-auth-unpacked = "hass-oidc-auth-${oidc-auth-version}";
in
{
  services.k3s.manifests = {
    home-assistant-namespace.content = {
      apiVersion = "v1";
      kind = "Namespace";
      metadata.name = namespace;
    };

    home-assistant-postgresql.content = {
      apiVersion = "acid.zalan.do/v1";
      kind = "postgresql";
      metadata = {
        name = "home-assistant-db";
        namespace = namespace;
      };
      spec = {
        teamId = "main";
        volume.size = "1Gi";
        numberOfInstances = 1;
        preparedDatabases.homeassistant = { };
        postgresql.version = "17";
        enableLogicalBackup = true;
      };
    };

    home-assistant-config.content = {
      apiVersion = "v1";
      kind = "ConfigMap";
      metadata = {
        name = "home-assistant-config";
        namespace = namespace;
      };
      data."configuration.yaml" = ''
        default_config:

        homeassistant:
          name: Home
          unit_system: metric
          country: RU
          currency: RUB
          time_zone: "Europe/Moscow"
          external_url: "https://home-assistant.iverian.ru"
          internal_url: "https://home-assistant.iverian.ru"

        recorder:
          db_url: !env_var HOME_ASSISTANT_DATABASE_URL

        automation: !include automations.yaml
        script: !include scripts.yaml
        scene: !include scenes.yaml

        auth_oidc:
          client_id: "homeassistant"
          discovery_url: "https://auth.iverian.ru/.well-known/openid-configuration"
          display_name: "Authelia"
          features:
            default_redirect: true
            force_https: true
          roles:
            admin: "admins"
      '';
    };

    home-assistant-pvc.content = {
      apiVersion = "v1";
      kind = "PersistentVolumeClaim";
      metadata = {
        name = "home-assistant-config";
        namespace = namespace;
      };
      spec = {
        accessModes = [ "ReadWriteOnce" ];
        resources.requests.storage = "5Gi";
      };
    };

    home-assistant-deployment.content = {
      apiVersion = "apps/v1";
      kind = "Deployment";
      metadata = {
        name = "home-assistant";
        namespace = namespace;
        annotations."reloader.stakater.com/auto" = "true";
      };
      spec = {
        replicas = 1;
        strategy.type = "Recreate";
        selector.matchLabels.app = "home-assistant";
        template = {
          metadata.labels.app = "home-assistant";
          spec = {
            securityContext.fsGroup = 1000;
            volumes = [
              {
                name = "config";
                persistentVolumeClaim.claimName = "home-assistant-config";
              }
              {
                name = "bootstrap-config";
                configMap.name = "home-assistant-config";
              }
              {
                name = "zigbee-serial";
                hostPath = {
                  path = "/dev/ttyUSB0";
                  type = "CharDevice";
                };
              }
              {
                name = "serial-by-id";
                hostPath = {
                  path = "/dev/serial/by-id";
                  type = "Directory";
                };
              }
              {
                name = "udev";
                hostPath = {
                  path = "/run/udev";
                  type = "Directory";
                };
              }
            ];
            initContainers = [
              {
                name = "install-oidc-auth";
                image = "alpine:3.20";
                command = [
                  "sh"
                  "-c"
                ];
                args = [
                  ''
                    set -eu
                    apk add --no-cache ca-certificates curl jq unzip
                    rm -rf /tmp/hass-oidc-auth /tmp/hass-oidc-auth.zip /tmp/${oidc-auth-unpacked}
                    curl --fail --location --retry 5 --retry-all-errors --output /tmp/hass-oidc-auth.zip ${oidc-auth-source}
                    unzip -q /tmp/hass-oidc-auth.zip -d /tmp
                    mkdir -p /config/custom_components
                    rm -rf /config/custom_components/auth_oidc
                    cp -R /tmp/${oidc-auth-unpacked}/custom_components/auth_oidc /config/custom_components/auth_oidc
                    cp /bootstrap/configuration.yaml /config/configuration.yaml
                    touch /config/automations.yaml /config/scripts.yaml /config/scenes.yaml
                    mkdir -p /config/.storage
                    cat > /config/.storage/onboarding <<'EOF'
                    {
                      "version": 4,
                      "minor_version": 1,
                      "key": "onboarding",
                      "data": {
                        "done": [
                          "user",
                          "core_config",
                          "analytics",
                          "integration"
                        ]
                      }
                    }
                    EOF

                    if [ ! -f /config/.storage/core.config_entries ]; then
                      cat > /config/.storage/core.config_entries <<'EOF'
                    {
                      "version": 1,
                      "minor_version": 5,
                      "key": "core.config_entries",
                      "data": {
                        "entries": []
                      }
                    }
                    EOF
                    fi

                    now="$(date -u '+%Y-%m-%dT%H:%M:%S+00:00')"
                    tmp="$(mktemp)"
                    jq \
                      --arg entry_id ${zha-entry-id} \
                      --arg now "$now" \
                      --arg path ${zigbee-device} \
                      '
                        def zha_entry($existing):
                          {
                            created_at: ($existing.created_at // $now),
                            data: {
                              device: {
                                path: $path,
                                baudrate: 115200,
                                flow_control: null
                              },
                              radio_type: "znp"
                            },
                            disabled_by: null,
                            discovery_keys: ($existing.discovery_keys // {}),
                            domain: "zha",
                            entry_id: ($existing.entry_id // $entry_id),
                            minor_version: 2,
                            modified_at: $now,
                            options: ($existing.options // {}),
                            pref_disable_new_entities: ($existing.pref_disable_new_entities // false),
                            pref_disable_polling: ($existing.pref_disable_polling // false),
                            source: ($existing.source // "user"),
                            subentries: ($existing.subentries // []),
                            title: ($existing.title // "ZHA"),
                            unique_id: ($existing.unique_id // null),
                            version: 5
                          };

                        .data.entries =
                          if any(.data.entries[]?; .domain == "zha") then
                            [.data.entries[] | if .domain == "zha" then zha_entry(.) else . end]
                          else
                            .data.entries + [zha_entry({})]
                          end
                      ' /config/.storage/core.config_entries > "$tmp"
                    mv "$tmp" /config/.storage/core.config_entries
                  ''
                ];
                volumeMounts = [
                  {
                    name = "config";
                    mountPath = "/config";
                  }
                  {
                    name = "bootstrap-config";
                    mountPath = "/bootstrap";
                    readOnly = true;
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
              }
            ];
            containers = [
              {
                name = "home-assistant";
                image = "ghcr.io/home-assistant/home-assistant:2026.10.2";
                imagePullPolicy = "Always";
                securityContext.privileged = true;
                ports = [
                  {
                    name = "http";
                    containerPort = 8123;
                    protocol = "TCP";
                  }
                ];
                env = [
                  {
                    name = "TZ";
                    value = "Europe/Moscow";
                  }
                  {
                    name = "POSTGRES_USER";
                    valueFrom.secretKeyRef = {
                      name = "postgres-home-assistant-db";
                      key = "username";
                    };
                  }
                  {
                    name = "POSTGRES_PASSWORD";
                    valueFrom.secretKeyRef = {
                      name = "postgres-home-assistant-db";
                      key = "password";
                    };
                  }
                  {
                    name = "HOME_ASSISTANT_DATABASE_URL";
                    value = "postgresql://$(POSTGRES_USER):$(POSTGRES_PASSWORD)@home-assistant-db:5432/homeassistant?sslmode=require";
                  }
                ];
                volumeMounts = [
                  {
                    name = "config";
                    mountPath = "/config";
                  }
                  {
                    name = "zigbee-serial";
                    mountPath = "/dev/ttyUSB0";
                  }
                  {
                    name = "serial-by-id";
                    mountPath = "/dev/serial/by-id";
                    readOnly = true;
                  }
                  {
                    name = "udev";
                    mountPath = "/run/udev";
                    readOnly = true;
                  }
                ];
                readinessProbe.httpGet = {
                  path = "/";
                  port = "http";
                };
                livenessProbe.httpGet = {
                  path = "/";
                  port = "http";
                };
                resources = {
                  requests = {
                    cpu = "250m";
                    memory = "512Mi";
                  };
                  limits = {
                    cpu = "2";
                    memory = "2Gi";
                  };
                };
              }
            ];
          };
        };
      };
    };

    home-assistant-service.content = {
      apiVersion = "v1";
      kind = "Service";
      metadata = {
        name = "home-assistant";
        namespace = namespace;
      };
      spec = {
        selector.app = "home-assistant";
        ports = [
          {
            name = "http";
            port = 80;
            protocol = "TCP";
            targetPort = "http";
          }
        ];
      };
    };

    home-assistant-httproute.content = {
      apiVersion = "gateway.networking.k8s.io/v1";
      kind = "HTTPRoute";
      metadata = {
        name = "home-assistant";
        namespace = namespace;
      };
      spec = {
        hostnames = [ "home-assistant.iverian.ru" ];
        parentRefs = [
          {
            group = "gateway.networking.k8s.io";
            kind = "Gateway";
            name = "main";
            namespace = "envoy-gateway-system";
          }
          {
            group = "gateway.networking.k8s.io";
            kind = "Gateway";
            name = "external";
            namespace = "envoy-gateway-system";
          }
        ];
        rules = [
          {
            backendRefs = [
              {
                group = "";
                kind = "Service";
                name = "home-assistant";
                port = 80;
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

  homelab.rcloneBackups.jobs.home-assistant = {
    inherit namespace;
    schedule = "0 5 * * *";
    source = "/config";
    excludes = [
      "home-assistant.log*"
      ".ha_run.lock"
      ".cache/**"
    ];
    volumes = [
      {
        name = "home-assistant-config";
        persistentVolumeClaim = {
          claimName = "home-assistant-config";
          readOnly = true;
        };
      }
    ];
    volumeMounts = [
      {
        name = "home-assistant-config";
        mountPath = "/config";
        readOnly = true;
      }
    ];
  };
}
