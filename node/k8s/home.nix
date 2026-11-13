{ config, ... }:
let
  namespace = "home";
  hostname = "home.iverian.ru";
  homepageServicePath = ../../services/homepage;
  homepageImageManifest = builtins.fromJSON (builtins.readFile (homepageServicePath + "/manifest.json"));
  homepageImageHash = builtins.substring 0 20 (builtins.hashString "sha256" (
    builtins.concatStringsSep "" (
      map
        (file: builtins.readFile (homepageServicePath + "/${file}"))
        ([ "Dockerfile" ] ++ homepageImageManifest.hashFiles)
    )
  ));
  homepageImage = "${homepageImageManifest.image}:${homepageImageHash}";
  converseServicePath = ../../services/converse;
  converseImageManifest = builtins.fromJSON (builtins.readFile (converseServicePath + "/manifest.json"));
  converseImageHash = builtins.substring 0 20 (builtins.hashString "sha256" (
    builtins.concatStringsSep "" (
      map
        (file: builtins.readFile (converseServicePath + "/${file}"))
        ([ "Dockerfile" ] ++ converseImageManifest.hashFiles)
    )
  ));
  converseImage = "${converseImageManifest.image}:${converseImageHash}";
  chatPath = config.sops.placeholder.chatPath;
  chatManifestNames = [
    "converse-config"
    "converse-deployment"
    "home-converse-route"
    "home-prosody-route"
  ];
in
{
  sops.secrets = {
    chatPath = { };
    homepageAuthSecret = { };
    homepageOidcClientSecret = { };
    prosodyAdminPassword = { };
  };

  sops.templates.home-secrets = {
    content = builtins.toJSON {
      apiVersion = "v1";
      kind = "Secret";
      metadata = {
        name = "home-secrets";
        namespace = namespace;
      };
      type = "Opaque";
      stringData = {
        homepage-auth-secret = config.sops.placeholder.homepageAuthSecret;
        homepage-nextcloud-password = config.sops.placeholder.nextcloudAdminPassword;
        homepage-oidc-client-secret = config.sops.placeholder.homepageOidcClientSecret;
        prosody-admin-password = config.sops.placeholder.prosodyAdminPassword;
      };
    };
    path = "/var/lib/rancher/k3s/server/manifests/home-secrets.json";
    restartUnits = [ "k3s.service" ];
  };

  sops.templates.home-chat-manifests = {
    content = builtins.toJSON {
      apiVersion = "v1";
      kind = "List";
      items = map (name: config.services.k3s.manifests.${name}.content) chatManifestNames;
    };
    path = "/var/lib/rancher/k3s/server/manifests/home-chat.json";
    restartUnits = [ "k3s.service" ];
  };

  services.k3s.manifests = {
    home-namespace.content = {
      apiVersion = "v1";
      kind = "Namespace";
      metadata.name = namespace;
    };

    homepage-service-account.content = {
      apiVersion = "v1";
      kind = "ServiceAccount";
      metadata = {
        name = "homepage";
        namespace = namespace;
      };
    };

    homepage-cluster-role.content = {
      apiVersion = "rbac.authorization.k8s.io/v1";
      kind = "ClusterRole";
      metadata.name = "homepage";
      rules = [
        {
          apiGroups = [ "" ];
          resources = [
            "nodes"
            "pods"
          ];
          verbs = [
            "get"
            "list"
          ];
        }
        {
          apiGroups = [ "metrics.k8s.io" ];
          resources = [
            "nodes"
            "pods"
          ];
          verbs = [
            "get"
            "list"
          ];
        }
      ];
    };

    homepage-cluster-role-binding.content = {
      apiVersion = "rbac.authorization.k8s.io/v1";
      kind = "ClusterRoleBinding";
      metadata.name = "homepage";
      roleRef = {
        apiGroup = "rbac.authorization.k8s.io";
        kind = "ClusterRole";
        name = "homepage";
      };
      subjects = [
        {
          kind = "ServiceAccount";
          name = "homepage";
          namespace = namespace;
        }
      ];
    };

    homepage-config.content = {
      apiVersion = "v1";
      kind = "ConfigMap";
      metadata = {
        name = "homepage-config";
        namespace = namespace;
      };
      data = {
        "bookmarks.yaml" = builtins.toJSON [ ];
        "custom.css" = "";
        "custom.js" = "";
        "docker.yaml" = builtins.toJSON { };
        "kubernetes.yaml" = builtins.toJSON {
          mode = "cluster";
          ingress = false;
          gateway = false;
        };
        "services.yaml" = builtins.toJSON [
          {
            "Основные сервисы" = [
              {
                Nextcloud = {
                  href = "https://nextcloud.iverian.ru";
                  description = "Файлы, календарь и заметки";
                  namespace = "nextcloud";
                  podSelector = "app.kubernetes.io/instance=nextcloud";
                  widget = {
                    type = "nextcloud";
                    url = "https://nextcloud.iverian.ru";
                    username = "admin";
                    password = "{{HOMEPAGE_VAR_NEXTCLOUD_PASSWORD}}";
                    fields = [
                      "freespace"
                      "activeusers"
                      "numfiles"
                      "numshares"
                    ];
                  };
                };
              }
              {
                Gitea = {
                  # The existing giteaUserToken is rejected by the live API.
                  # Keep the native widget disabled until a replacement token is stored in SOPS.
                  href = "https://gitea.iverian.ru";
                  description = "Git-репозитории";
                  namespace = "gitea";
                  podSelector = "app.kubernetes.io/instance=gitea";
                  siteMonitor = "http://gitea-http.gitea.svc.cluster.local:3000";
                };
              }
              {
                "Home Assistant" = {
                  # The native widget requires a long-lived access token created by Home Assistant.
                  href = "https://home-assistant.iverian.ru";
                  description = "Умный дом";
                  namespace = "home-assistant";
                  podSelector = "app=home-assistant";
                  siteMonitor = "http://home-assistant.home-assistant.svc.cluster.local";
                };
              }
            ];
          }
          {
            "Медиа" = [
              {
                Jellyfin = {
                  # The native widget requires an API key created by Jellyfin.
                  href = "https://jellyfin.iverian.ru";
                  description = "Фильмы и сериалы";
                  namespace = "media";
                  podSelector = "app=jellyfin";
                  siteMonitor = "http://jellyfin.media.svc.cluster.local";
                };
              }
              {
                Transmission = {
                  href = "https://transmission.iverian.ru";
                  description = "Загрузки";
                  namespace = "media";
                  podSelector = "app=transmission";
                  widget = {
                    type = "transmission";
                    url = "http://transmission-rpc.media.svc.cluster.local:9091";
                    username = "homepage";
                    password = "";
                    rpcUrl = "/transmission/";
                  };
                };
              }
            ];
          }
          {
            "Игры" = [
              {
                "Foundry VTT" = {
                  href = "https://foundry.iverian.ru";
                  description = "Виртуальный игровой стол";
                  namespace = "foundry";
                  podSelector = "app=foundry";
                  siteMonitor = "http://foundry.foundry.svc.cluster.local:30000";
                };
              }
              {
                "Карты для RPG" = {
                  href = "https://rpg-cards.iverian.ru";
                  description = "Генератор игровых карт";
                  namespace = "rpg-cards";
                  podSelector = "app=rpg-cards";
                  siteMonitor = "http://rpg-cards.rpg-cards.svc.cluster.local:8080";
                };
              }
            ];
          }
          {
            "Инфраструктура" = [
              {
                Authelia = {
                  href = "https://auth.iverian.ru";
                  description = "Единый вход и двухфакторная аутентификация";
                  namespace = "authelia";
                  podSelector = "app.kubernetes.io/instance=authelia";
                  siteMonitor = "http://authelia.authelia.svc.cluster.local";
                };
              }
            ];
          }
        ];
        "settings.yaml" = builtins.toJSON {
          title = "Домашние сервисы";
          description = "Панель домашних сервисов";
          language = "ru";
          target = "_self";
          headerStyle = "clean";
          cardStyle = "hairline";
          statusStyle = "dot";
          useEqualHeights = true;
          disableUpdateCheck = true;
          disableIndexing = true;
          quicklaunch = {
            hideInternetSearch = true;
            showSearchSuggestions = false;
          };
          layout = {
            "Основные сервисы" = {
              style = "row";
              columns = 3;
            };
            "Медиа" = {
              style = "row";
              columns = 2;
            };
            "Игры" = {
              style = "row";
              columns = 2;
            };
            "Инфраструктура" = {
              style = "row";
              columns = 1;
            };
          };
        };
        "widgets.yaml" = builtins.toJSON [
          {
            kubernetes = {
              cluster = {
                show = true;
                cpu = true;
                memory = true;
                showLabel = true;
                label = "Кластер";
              };
              nodes = {
                show = true;
                cpu = true;
                memory = true;
                showLabel = true;
              };
            };
          }
          {
            datetime = {
              text_size = "xl";
              format = {
                dateStyle = "long";
                timeStyle = "short";
                hour12 = false;
              };
            };
          }
        ];
      };
    };

    homepage-deployment.content = {
      apiVersion = "apps/v1";
      kind = "Deployment";
      metadata = {
        name = "homepage";
        namespace = namespace;
        labels.app = "homepage";
        annotations = {
          "configmap.reloader.stakater.com/reload" = "homepage-config";
          "secret.reloader.stakater.com/reload" = "home-secrets";
        };
      };
      spec = {
        replicas = 1;
        selector.matchLabels.app = "homepage";
        template = {
          metadata.labels.app = "homepage";
          spec = {
            serviceAccountName = "homepage";
            automountServiceAccountToken = true;
            securityContext = {
              runAsNonRoot = true;
              runAsUser = 1000;
              runAsGroup = 1000;
              fsGroup = 1000;
              seccompProfile.type = "RuntimeDefault";
            };
            containers = [
              {
                name = "homepage";
                image = homepageImage;
                imagePullPolicy = "Never";
                securityContext = {
                  allowPrivilegeEscalation = false;
                  capabilities.drop = [ "ALL" ];
                };
                env = [
                  {
                    name = "HOMEPAGE_ALLOWED_HOSTS";
                    value = hostname;
                  }
                  {
                    name = "HOMEPAGE_AUTH_ENABLED";
                    value = "true";
                  }
                  {
                    name = "HOMEPAGE_AUTH_SECRET";
                    valueFrom.secretKeyRef = {
                      name = "home-secrets";
                      key = "homepage-auth-secret";
                    };
                  }
                  {
                    name = "HOMEPAGE_EXTERNAL_URL";
                    value = "https://${hostname}";
                  }
                  {
                    name = "HOMEPAGE_OIDC_ISSUER";
                    value = "https://auth.iverian.ru";
                  }
                  {
                    name = "HOMEPAGE_OIDC_CLIENT_ID";
                    value = "homepage";
                  }
                  {
                    name = "HOMEPAGE_OIDC_CLIENT_SECRET";
                    valueFrom.secretKeyRef = {
                      name = "home-secrets";
                      key = "homepage-oidc-client-secret";
                    };
                  }
                  {
                    name = "HOMEPAGE_OIDC_NAME";
                    value = "Authelia";
                  }
                  {
                    name = "HOMEPAGE_OIDC_SCOPE";
                    value = "openid email profile groups";
                  }
                  {
                    name = "HOMEPAGE_OIDC_AUTO_LOGIN";
                    value = "true";
                  }
                  {
                    name = "HOMEPAGE_VAR_NEXTCLOUD_PASSWORD";
                    valueFrom.secretKeyRef = {
                      name = "home-secrets";
                      key = "homepage-nextcloud-password";
                    };
                  }
                  {
                    name = "LOG_TARGETS";
                    value = "stdout";
                  }
                ];
                ports = [
                  {
                    name = "http";
                    containerPort = 3000;
                    protocol = "TCP";
                  }
                ];
                readinessProbe.httpGet = {
                  path = "/api/healthcheck";
                  port = "http";
                  httpHeaders = [
                    {
                      name = "Host";
                      value = hostname;
                    }
                  ];
                };
                livenessProbe.httpGet = {
                  path = "/api/healthcheck";
                  port = "http";
                  httpHeaders = [
                    {
                      name = "Host";
                      value = hostname;
                    }
                  ];
                };
                resources = {
                  requests = {
                    cpu = "100m";
                    memory = "128Mi";
                  };
                  limits.memory = "512Mi";
                };
                volumeMounts = map
                  (file: {
                    name = "config";
                    mountPath = "/app/config/${file}";
                    subPath = file;
                    readOnly = true;
                  })
                  [
                    "bookmarks.yaml"
                    "custom.css"
                    "custom.js"
                    "docker.yaml"
                    "kubernetes.yaml"
                    "services.yaml"
                    "settings.yaml"
                    "widgets.yaml"
                  ]
                ++ [
                  {
                    name = "logs";
                    mountPath = "/app/config/logs";
                  }
                ];
              }
            ];
            volumes = [
              {
                name = "config";
                configMap.name = "homepage-config";
              }
              {
                name = "logs";
                emptyDir = { };
              }
            ];
          };
        };
      };
    };

    homepage-service.content = {
      apiVersion = "v1";
      kind = "Service";
      metadata = {
        name = "homepage";
        namespace = namespace;
      };
      spec = {
        selector.app = "homepage";
        ports = [
          {
            name = "http";
            port = 3000;
            targetPort = "http";
            protocol = "TCP";
          }
        ];
      };
    };

    prosody-config.content = {
      apiVersion = "v1";
      kind = "ConfigMap";
      metadata = {
        name = "prosody-config";
        namespace = namespace;
      };
      data."prosody.cfg.lua" = ''
        admins = { "iverian@${hostname}" }

        authentication = "internal_hashed"
        allow_registration = false

        c2s_ports = {}
        s2s_ports = {}
        http_ports = { 5280 }
        https_ports = {}
        http_interfaces = { "*" }
        consider_websocket_secure = true

        modules_enabled = {
          "disco";
          "roster";
          "saslauth";
          "tls";
          "blocklist";
          "bookmarks";
          "carbons";
          "pep";
          "private";
          "vcard4";
          "vcard_legacy";
          "limits";
          "ping";
          "smacks";
          "time";
          "uptime";
          "version";
          "websocket";
          "offline";
        }

        modules_disabled = {
          "admin_shell";
          "bosh";
          "http_file_share";
          "mam";
          "register";
          "s2s";
        }

        storage = "internal"
        archive_expires_after = "1d"
        default_archive_policy = false
        log = { warn = "*console" }

        VirtualHost "${hostname}"
          cross_domain_websocket = { "https://${hostname}" }

        Component "rooms.${hostname}" "muc"
          name = "Private rooms"
          restrict_room_creation = "local"
          muc_room_default_public = false
          muc_room_default_public_jids = false
          muc_room_default_members_only = true
          modules_disabled = { "muc_mam" }
      '';
    };

    prosody-pvc.content = {
      apiVersion = "v1";
      kind = "PersistentVolumeClaim";
      metadata = {
        name = "prosody-data";
        namespace = namespace;
      };
      spec = {
        accessModes = [ "ReadWriteOnce" ];
        storageClassName = "local-path";
        resources.requests.storage = "1Gi";
      };
    };

    prosody-deployment.content = {
      apiVersion = "apps/v1";
      kind = "Deployment";
      metadata = {
        name = "prosody";
        namespace = namespace;
        labels.app = "prosody";
        annotations = {
          "configmap.reloader.stakater.com/reload" = "prosody-config";
          "secret.reloader.stakater.com/reload" = "home-secrets";
        };
      };
      spec = {
        replicas = 1;
        strategy.type = "Recreate";
        selector.matchLabels.app = "prosody";
        template = {
          metadata.labels.app = "prosody";
          spec = {
            initContainers = [
              {
                name = "prepare-data-directory";
                image = "prosodyim/prosody:13.0";
                imagePullPolicy = "IfNotPresent";
                command = [
                  "/bin/sh"
                  "-c"
                ];
                args = [ "chown -R 100:102 /var/lib/prosody" ];
                securityContext = {
                  runAsUser = 0;
                  runAsGroup = 0;
                  allowPrivilegeEscalation = false;
                  capabilities = {
                    drop = [ "ALL" ];
                    add = [ "CHOWN" ];
                  };
                };
                volumeMounts = [
                  {
                    name = "data";
                    mountPath = "/var/lib/prosody";
                  }
                ];
              }
            ];
            containers = [
              {
                name = "prosody";
                image = "prosodyim/prosody:13.0";
                imagePullPolicy = "IfNotPresent";
                env = [
                  {
                    name = "LOCAL";
                    value = "iverian";
                  }
                  {
                    name = "DOMAIN";
                    value = hostname;
                  }
                  {
                    name = "PASSWORD";
                    valueFrom.secretKeyRef = {
                      name = "home-secrets";
                      key = "prosody-admin-password";
                    };
                  }
                ];
                ports = [
                  {
                    name = "websocket";
                    containerPort = 5280;
                    protocol = "TCP";
                  }
                ];
                readinessProbe = {
                  tcpSocket.port = "websocket";
                  initialDelaySeconds = 5;
                };
                livenessProbe = {
                  tcpSocket.port = "websocket";
                  initialDelaySeconds = 15;
                };
                resources = {
                  requests = {
                    cpu = "25m";
                    memory = "64Mi";
                  };
                  limits.memory = "256Mi";
                };
                volumeMounts = [
                  {
                    name = "config";
                    mountPath = "/etc/prosody/prosody.cfg.lua";
                    subPath = "prosody.cfg.lua";
                    readOnly = true;
                  }
                  {
                    name = "data";
                    mountPath = "/var/lib/prosody";
                  }
                ];
              }
            ];
            volumes = [
              {
                name = "config";
                configMap.name = "prosody-config";
              }
              {
                name = "data";
                persistentVolumeClaim.claimName = "prosody-data";
              }
            ];
          };
        };
      };
    };

    prosody-service.content = {
      apiVersion = "v1";
      kind = "Service";
      metadata = {
        name = "prosody";
        namespace = namespace;
      };
      spec = {
        selector.app = "prosody";
        ports = [
          {
            name = "websocket";
            port = 5280;
            targetPort = "websocket";
            protocol = "TCP";
          }
        ];
      };
    };

    converse-config.content = {
      apiVersion = "v1";
      kind = "ConfigMap";
      metadata = {
        name = "converse-config";
        namespace = namespace;
      };
      data = {
        "index.html" = ''
          <!doctype html>
          <html lang="ru">
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
              <meta name="theme-color" content="#111827">
              <title>Workspace</title>
              <link rel="manifest" href="${chatPath}/manifest.webmanifest">
              <link rel="icon" href="${chatPath}/icon.svg" type="image/svg+xml">
              <link rel="stylesheet" href="${chatPath}/dist/converse.css">
            </head>
            <body class="converse-fullscreen">
              <noscript>Для работы требуется JavaScript.</noscript>
              <script type="module" src="${chatPath}/dist/converse.js"></script>
              <script type="module" src="${chatPath}/config.js"></script>
            </body>
          </html>
        '';
        "config.js" = ''
          converse.initialize({
            assets_path: '${chatPath}/dist',
            authentication: 'login',
            websocket_url: 'wss://${hostname}${chatPath}/socket',
            discover_connection_methods: false,
            locked_domain: '${hostname}',
            muc_domain: 'rooms.${hostname}',
            locked_muc_domain: 'hidden',
            allow_registration: false,
            message_archiving: 'never',
            omemo_default: true,
            view_mode: 'fullscreen',
            i18n: 'ru',
            auto_reconnect: true,
            persistent_store: 'IndexedDB',
            loglevel: 'warn'
          });

          if ('serviceWorker' in navigator) {
            navigator.serviceWorker.register('${chatPath}/service-worker.js', { scope: '${chatPath}/' });
          }
        '';
        "manifest.webmanifest" = builtins.toJSON {
          name = "Workspace";
          short_name = "Workspace";
          start_url = "${chatPath}/";
          scope = "${chatPath}/";
          display = "standalone";
          background_color = "#111827";
          theme_color = "#111827";
          icons = [
            {
              src = "${chatPath}/icon.svg";
              sizes = "any";
              type = "image/svg+xml";
              purpose = "any maskable";
            }
          ];
        };
        "service-worker.js" = ''
          self.addEventListener('install', () => self.skipWaiting());
          self.addEventListener('activate', event => event.waitUntil(self.clients.claim()));
          self.addEventListener('fetch', () => {});
        '';
        "icon.svg" = ''
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
            <rect width="512" height="512" rx="112" fill="#111827"/>
            <path d="M128 152h256v48H128zm0 80h256v48H128zm0 80h160v48H128z" fill="#d1d5db"/>
          </svg>
        '';
        "nginx.conf" = ''
          server {
            listen 8080;
            server_name _;
            root /www;

            add_header X-Content-Type-Options "nosniff" always;
            add_header Referrer-Policy "no-referrer" always;
            add_header X-Frame-Options "DENY" always;
            add_header Permissions-Policy "camera=(), microphone=(), geolocation=()" always;
            add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob: https:; font-src 'self' data:; connect-src 'self' wss://${hostname}; media-src 'self' blob: https:; worker-src 'self' blob:; object-src 'none'; base-uri 'self'; frame-ancestors 'none'" always;

            location = /healthz {
              access_log off;
              return 200 "ok\n";
            }

            location = ${chatPath} {
              return 308 ${chatPath}/;
            }

            location ${chatPath}/dist/ {
              alias /opt/converse/dist/;
            }

            location ${chatPath}/ {
              try_files $uri $uri/ ${chatPath}/index.html;
            }
          }
        '';
      };
    };
    converse-config.enable = false;

    converse-deployment.content = {
      apiVersion = "apps/v1";
      kind = "Deployment";
      metadata = {
        name = "converse";
        namespace = namespace;
        labels.app = "converse";
        annotations."configmap.reloader.stakater.com/reload" = "converse-config";
      };
      spec = {
        replicas = 1;
        selector.matchLabels.app = "converse";
        template = {
          metadata.labels.app = "converse";
          spec = {
            containers = [
              {
                name = "nginx";
                image = converseImage;
                imagePullPolicy = "Never";
                ports = [
                  {
                    name = "http";
                    containerPort = 8080;
                    protocol = "TCP";
                  }
                ];
                readinessProbe.httpGet = {
                  path = "${chatPath}/";
                  port = "http";
                };
                livenessProbe.httpGet = {
                  path = "${chatPath}/";
                  port = "http";
                };
                resources = {
                  requests = {
                    cpu = "10m";
                    memory = "32Mi";
                  };
                  limits.memory = "128Mi";
                };
                volumeMounts = [
                  {
                    name = "public-config";
                    mountPath = "/www${chatPath}";
                    readOnly = true;
                  }
                  {
                    name = "nginx-config";
                    mountPath = "/etc/nginx/conf.d/default.conf";
                    subPath = "nginx.conf";
                    readOnly = true;
                  }
                ];
              }
            ];
            volumes = [
              {
                name = "public-config";
                configMap = {
                  name = "converse-config";
                  items = map
                    (key: {
                      inherit key;
                      path = key;
                    })
                    [ "index.html" "config.js" "manifest.webmanifest" "service-worker.js" "icon.svg" ];
                };
              }
              {
                name = "nginx-config";
                configMap = {
                  name = "converse-config";
                  items = [
                    {
                      key = "nginx.conf";
                      path = "nginx.conf";
                    }
                  ];
                };
              }
            ];
          };
        };
      };
    };
    converse-deployment.enable = false;

    converse-service.content = {
      apiVersion = "v1";
      kind = "Service";
      metadata = {
        name = "converse";
        namespace = namespace;
      };
      spec = {
        selector.app = "converse";
        ports = [
          {
            name = "http";
            port = 8080;
            targetPort = "http";
            protocol = "TCP";
          }
        ];
      };
    };

    home-homepage-route.content = {
      apiVersion = "gateway.networking.k8s.io/v1";
      kind = "HTTPRoute";
      metadata = {
        name = "home-homepage";
        namespace = namespace;
      };
      spec = {
        hostnames = [ hostname ];
        parentRefs = [
          {
            name = "main";
            namespace = "envoy-gateway-system";
            sectionName = "https";
          }
          {
            name = "external";
            namespace = "envoy-gateway-system";
            sectionName = "public-secure";
          }
        ];
        rules = [
          {
            matches = [ { path = { type = "PathPrefix"; value = "/"; }; } ];
            backendRefs = [ { name = "homepage"; port = 3000; } ];
          }
        ];
      };
    };

    home-converse-route.content = {
      apiVersion = "gateway.networking.k8s.io/v1";
      kind = "HTTPRoute";
      metadata = {
        name = "home-converse";
        namespace = namespace;
      };
      spec = {
        hostnames = [ hostname ];
        parentRefs = [
          {
            name = "main";
            namespace = "envoy-gateway-system";
            sectionName = "https";
          }
          {
            name = "external";
            namespace = "envoy-gateway-system";
            sectionName = "public-secure";
          }
        ];
        rules = [
          {
            matches = [ { path = { type = "PathPrefix"; value = chatPath; }; } ];
            backendRefs = [ { name = "converse"; port = 8080; } ];
          }
        ];
      };
    };
    home-converse-route.enable = false;

    home-prosody-route.content = {
      apiVersion = "gateway.networking.k8s.io/v1";
      kind = "HTTPRoute";
      metadata = {
        name = "home-prosody";
        namespace = namespace;
      };
      spec = {
        hostnames = [ hostname ];
        parentRefs = [
          {
            name = "main";
            namespace = "envoy-gateway-system";
            sectionName = "https";
          }
          {
            name = "external";
            namespace = "envoy-gateway-system";
            sectionName = "public-secure";
          }
        ];
        rules = [
          {
            matches = [ { path = { type = "Exact"; value = "${chatPath}/socket"; }; } ];
            filters = [
              {
                type = "URLRewrite";
                urlRewrite.path = {
                  type = "ReplaceFullPath";
                  replaceFullPath = "/xmpp-websocket";
                };
              }
            ];
            backendRefs = [ { name = "prosody"; port = 5280; } ];
          }
        ];
      };
    };
    home-prosody-route.enable = false;

    home-prosody-timeout.content = {
      apiVersion = "gateway.envoyproxy.io/v1alpha1";
      kind = "BackendTrafficPolicy";
      metadata = {
        name = "home-prosody-timeout";
        namespace = namespace;
      };
      spec = {
        targetRefs = [
          {
            group = "gateway.networking.k8s.io";
            kind = "HTTPRoute";
            name = "home-prosody";
          }
        ];
        timeout.http.requestTimeout = "0s";
      };
    };

  };
}
