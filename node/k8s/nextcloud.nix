{ config, ... }:
let
  namespace = "nextcloud";
  rclone-config = "nextcloud-rclone-config";
in
{
  sops = {
    secrets = {
      nextcloudAdminPassword = { };
      nextcloudOidcClientSecret = { };
      rcloneConfigB64 = { };
    };
    templates = {
      nextcloud-admin = {
        content = builtins.toJSON {
          apiVersion = "v1";
          kind = "Secret";
          metadata = {
            name = "nextcloud-admin";
            namespace = namespace;
          };
          stringData = {
            username = "admin";
            password = config.sops.placeholder.nextcloudAdminPassword;
          };
        };
        path = "/var/lib/rancher/k3s/server/manifests/nextcloud-admin-secret.json";
      };
      nextcloud-oidc = {
        content = builtins.toJSON {
          apiVersion = "v1";
          kind = "Secret";
          metadata = {
            name = "nextcloud-oidc";
            namespace = namespace;
          };
          stringData = {
            clientSecret = config.sops.placeholder.nextcloudOidcClientSecret;
          };
        };
        path = "/var/lib/rancher/k3s/server/manifests/nextcloud-oidc-secret.json";
      };
      nextcloud-rclone-config = {
        content = builtins.toJSON {
          apiVersion = "v1";
          kind = "Secret";
          metadata = {
            name = rclone-config;
            namespace = namespace;
          };
          data = {
            "rclone.conf" = config.sops.placeholder.rcloneConfigB64;
          };
        };
        path = "/var/lib/rancher/k3s/server/manifests/nextcloud-rclone-config.json";
      };
    };
  };

  services.k3s.manifests = {
    nextcloud-namespace.content = {
      apiVersion = "v1";
      kind = "Namespace";
      metadata.name = namespace;
    };

    nextcloud-postgresql.content = {
      apiVersion = "acid.zalan.do/v1";
      kind = "postgresql";
      metadata = {
        name = "nextcloud-db";
        namespace = namespace;
      };
      spec = {
        teamId = "main";
        volume.size = "5Gi";
        numberOfInstances = 1;
        preparedDatabases.nextcloud = { };
        postgresql.version = "17";
        enableLogicalBackup = true;
      };
    };

    nextcloud-valkey.content = {
      apiVersion = "hyperspike.io/v1";
      kind = "Valkey";
      metadata = {
        name = "nextcloud-cache";
        namespace = namespace;
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

    nextcloud-backend-policy.content = {
      apiVersion = "gateway.envoyproxy.io/v1alpha1";
      kind = "BackendTrafficPolicy";
      metadata = {
        name = "nextcloud-timeout";
        namespace = namespace;
      };
      spec = {
        targetRefs = [
          {
            group = "gateway.networking.k8s.io";
            kind = "HTTPRoute";
            name = "nextcloud";
          }
        ];
        timeout.http.requestTimeout = "1h";
      };
    };

    nextcloud-rclone-backup.content = {
      apiVersion = "batch/v1";
      kind = "CronJob";
      metadata = {
        name = "rclone-backup";
        namespace = namespace;
      };
      spec = {
        schedule = "0 3 * * *";
        concurrencyPolicy = "Forbid";
        successfulJobsHistoryLimit = 3;
        failedJobsHistoryLimit = 3;
        jobTemplate.spec.template = {
          metadata.annotations."reloader.stakater.com/auto" = "true";
          spec = {
            restartPolicy = "OnFailure";
            volumes = [
              {
                name = "nextcloud-data";
                persistentVolumeClaim = {
                  claimName = "nextcloud-nextcloud";
                  readOnly = true;
                };
              }
              {
                name = "config-ro";
                secret.secretName = rclone-config;
              }
              {
                name = "state";
                emptyDir = { };
              }
            ];
            initContainers = [
              {
                name = "setup";
                image = "rancher/mirrored-library-busybox:1.36.1";
                command = [
                  "sh"
                  "-c"
                ];
                args = [ "cp /config-ro/rclone.conf /state/rclone.conf && mkdir -p /state/cache" ];
                volumeMounts = [
                  {
                    name = "config-ro";
                    mountPath = "/config-ro";
                  }
                  {
                    name = "state";
                    mountPath = "/state";
                  }
                ];
                resources = {
                  requests = {
                    cpu = "50m";
                    memory = "64Mi";
                  };
                  limits = {
                    cpu = "100m";
                    memory = "128Mi";
                  };
                };
              }
            ];
            containers = [
              {
                name = "rclone";
                image = "rclone/rclone:sha-0157a1f";
                args = [
                  "sync"
                  "/data/data"
                  "crypt:nextcloud"
                  "--config"
                  "/state/rclone.conf"
                  "--cache-dir"
                  "/state/cache"
                  "--include"
                  "*/files/**"
                  "--delete-excluded"
                  "--log-level"
                  "INFO"
                  "--delete-during"
                ];
                volumeMounts = [
                  {
                    name = "nextcloud-data";
                    mountPath = "/data";
                    readOnly = true;
                  }
                  {
                    name = "state";
                    mountPath = "/state";
                  }
                ];
                resources = {
                  requests = {
                    cpu = "100m";
                    memory = "256Mi";
                  };
                  limits = {
                    cpu = "1000m";
                    memory = "1Gi";
                  };
                };
              }
            ];
          };
        };
      };
    };

  };

  services.k3s.autoDeployCharts.nextcloud = {
    name = "nextcloud";
    repo = "https://nextcloud.github.io/helm/";
    version = "9.0.6";
    hash = "sha256-pBnD+LiznV1ckj0ljYcDxBtSZCf6HoqUV6p41E6lEh4=";
    targetNamespace = namespace;
    createNamespace = false;
    values = {
      nextcloud = {
        host = "nextcloud.iverian.ru";
        existingSecret = {
          enabled = true;
          secretName = "nextcloud-admin";
          usernameKey = "username";
          passwordKey = "password";
        };
        extraEnv = [
          {
            name = "NEXTCLOUD_OIDC_SECRET";
            valueFrom.secretKeyRef = {
              name = "nextcloud-oidc";
              key = "clientSecret";
            };
          }
          {
            name = "OVERWRITEPROTOCOL";
            value = "https";
          }
          {
            name = "OVERWRITEHOST";
            value = "nextcloud.iverian.ru";
          }
          {
            name = "OVERWRITECLIURL";
            value = "https://nextcloud.iverian.ru";
          }
          {
            name = "TRUSTED_PROXIES";
            value = "10.42.0.0/16";
          }
          {
            name = "PGSSLCERT";
            value = "/tmp/no-client-cert";
          }
          {
            name = "PGSSLKEY";
            value = "/tmp/no-client-cert";
          }
        ];
        configs."local-access.config.php" = ''
          <?php
          $CONFIG = array (
            'allow_local_remote_servers' => true,
          );
        '';
        configs."trusted-domains.config.php" = ''
          <?php
          $CONFIG = array (
            'trusted_domains' =>
            array (
              0 => 'nextcloud.iverian.ru',
              1 => 'localhost',
            ),
          );
        '';
        hooks.before-starting = ''
          # Install only if not yet done (entrypoint may have already handled it)
          if ! php /var/www/html/occ status 2>/dev/null | grep -q "installed: true"; then
            echo "==> Waiting for PostgreSQL..."
            until php /var/www/html/occ status 2>/dev/null | grep -q "installed:"; do
              sleep 5
            done
            echo "==> Installing Nextcloud..."
            php /var/www/html/occ maintenance:install \
              --database=pgsql \
              --database-host=nextcloud-db \
              --database-name=nextcloud \
              --database-user=postgres \
              --database-pass="''${POSTGRES_PASSWORD}" \
              --admin-user="''${NEXTCLOUD_ADMIN_USER}" \
              --admin-pass="''${NEXTCLOUD_ADMIN_PASSWORD}"
          fi

          # Always configure OIDC (idempotent — runs on every start)
          php /var/www/html/occ app:install user_oidc || true
          php /var/www/html/occ app:enable user_oidc || true
          php /var/www/html/occ user_oidc:provider authelia \
            --clientid=nextcloud \
            --clientsecret="''${NEXTCLOUD_OIDC_SECRET}" \
            --discoveryuri=https://auth.iverian.ru/.well-known/openid-configuration \
            --unique-uid=0 \
            --mapping-groups=groups || true
          php /var/www/html/occ config:app:set user_oidc allow_multiple_user_backends --value=0 || true

          # Disable unused features (reduces attack surface)
          php /var/www/html/occ app:disable federation || true
          php /var/www/html/occ app:disable sharebymail || true
          php /var/www/html/occ app:enable notes || true
          php /var/www/html/occ config:system:set lost_password_link --value=disabled || true
        '';
      };

      internalDatabase.enabled = false;

      externalDatabase = {
        enabled = true;
        type = "postgresql";
        host = "nextcloud-db";
        user = "postgres";
        database = "nextcloud";
        existingSecret = {
          enabled = true;
          secretName = "postgres-nextcloud-db";
          usernameKey = "username";
          passwordKey = "password";
        };
      };

      redis.enabled = false;

      externalRedis = {
        enabled = true;
        host = "nextcloud-cache";
        port = "6379";
      };

      persistence = {
        enabled = true;
        storageClass = "storage";
        size = "200Gi";
      };

      ingress.enabled = false;

      # Kubelet probes hit the pod IP which is not in trusted_domains.
      # Disable httpGet probes; the container manages its own lifecycle.
      livenessProbe.enabled = false;
      readinessProbe.enabled = false;

      httpRoute = {
        enabled = true;
        hostnames = [ "nextcloud.iverian.ru" ];
        parentRefs = [
          {
            name = "external";
            namespace = "envoy-gateway-system";
          }
          {
            name = "main";
            namespace = "envoy-gateway-system";
          }
        ];
        rules = [
          {
            matches = [
              {
                path = {
                  type = "PathPrefix";
                  value = "/";
                };
              }
            ];
            filters = [
              {
                type = "ResponseHeaderModifier";
                responseHeaderModifier.add = [
                  {
                    name = "Strict-Transport-Security";
                    value = "max-age=31536000; includeSubDomains; preload";
                  }
                ];
              }
            ];
          }
        ];
      };
    };
  };
}
