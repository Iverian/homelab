{ config, ... }:
let
  namespace = "postgres-operator";
in
{
  services.k3s.autoDeployCharts.postgres-operator = {
    name = "postgres-operator";
    repo = "https://opensource.zalando.com/postgres-operator/charts/postgres-operator";
    version = "1.15.1";
    hash = "sha256-nz7cPXlhBcAsBOquKKeOWPsIwYR6neASJF/WrCwNLAA=";
    targetNamespace = namespace;
    createNamespace = true;
    values = {
      enableJsonLogging = true;
      configKubernetes.secret_name_template = "{username}-{cluster}";
      configLogicalBackup = {
        logical_backup_s3_bucket = "postgres";
        logical_backup_s3_endpoint = "http://rclone-serve.backup.svc.cluster.local";
        logical_backup_s3_access_key_id = "user";
        logical_backup_s3_secret_access_key = "pass";
        logical_backup_s3_retention_time = "2 weeks";
      };
    };
  };
}
