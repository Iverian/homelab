{ config, ... }:
let
  namespace = "postgres-operator";
in
{
  sops.secrets.postgresExporterPassword = { };

  sops.templates = {
    postgres-infrastructure-roles = {
      content = builtins.toJSON {
        apiVersion = "v1";
        kind = "Secret";
        metadata = {
          name = "postgresql-infrastructure-roles";
          inherit namespace;
        };
        type = "Opaque";
        stringData = {
          user1 = "postgres_exporter";
          password1 = config.sops.placeholder.postgresExporterPassword;
          inrole1 = "pg_monitor";
        };
      };
      path = "/var/lib/rancher/k3s/server/manifests/postgres-infrastructure-roles.json";
      restartUnits = [ "k3s.service" ];
    };

    postgres-exporter = {
      content = builtins.toJSON {
        apiVersion = "v1";
        kind = "Secret";
        metadata = {
          name = "postgres-exporter";
          namespace = "monitoring";
        };
        type = "Opaque";
        stringData."postgres_exporter.yml" = builtins.toJSON {
          auth_modules.postgres = {
            type = "userpass";
            userpass = {
              username = "postgres_exporter";
              password = config.sops.placeholder.postgresExporterPassword;
            };
            options.sslmode = "require";
          };
        };
      };
      path = "/var/lib/rancher/k3s/server/manifests/postgres-exporter-secret.json";
      restartUnits = [ "k3s.service" ];
    };
  };

  services.k3s.autoDeployCharts.postgres-operator = {
    name = "postgres-operator";
    repo = "https://opensource.zalando.com/postgres-operator/charts/postgres-operator";
    version = "1.15.1";
    hash = "sha256-nz7cPXlhBcAsBOquKKeOWPsIwYR6neASJF/WrCwNLAA=";
    targetNamespace = namespace;
    createNamespace = true;
    values = {
      enableJsonLogging = true;
      configKubernetes = {
        secret_name_template = "{username}-{cluster}";
        infrastructure_roles_secret_name = "postgresql-infrastructure-roles";
      };
      configLogicalBackup = {
        logical_backup_s3_bucket = "postgres";
        logical_backup_s3_endpoint = "http://rclone-serve.backup.svc.cluster.local";
        logical_backup_s3_access_key_id = "user";
        logical_backup_s3_secret_access_key = "pass";
        logical_backup_s3_retention_time = "30 days";
      };
    };
  };
}
