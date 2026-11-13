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
in
{
  sops.secrets = {
    homepageAuthSecret = { };
    homepageOidcClientSecret = { };
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
      };
    };
    path = "/var/lib/rancher/k3s/server/manifests/home-secrets.json";
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
              {
                Grafana = {
                  href = "https://grafana.iverian.ru";
                  description = "Мониторинг и дашборды";
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
              columns = 2;
            };
          };
        };
        "widgets.yaml" = builtins.toJSON [
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

  };
}
