{ config, lib, ... }:
let
  inherit (lib)
    concatMap
    escapeShellArgs
    filterAttrs
    mapAttrs'
    mkEnableOption
    mkIf
    mkOption
    nameValuePair
    types
    ;

  cfg = config.homelab.rcloneBackups;
  enabledJobs = filterAttrs (_: job: job.enable) cfg.jobs;
  image = "rclone/rclone:sha-0157a1f";
  remotes =
    lib.optionals cfg.yandex.enable [
      {
        name = "yandex";
        remote = "yandex-crypt";
      }
    ]
    ++ lib.optionals cfg.mega.enable [
      {
        name = "mega";
        remote = "mega-crypt";
      }
    ];
  remoteNames = lib.concatMapStringsSep " " (remote: remote.name) remotes;

  mkScript =
    job: remote:
    let
      commonArgs = [
        job.command
        job.source
        "${remote.remote}:${job.destination}"
        "--config"
        "/state/${remote.name}/rclone.conf"
        "--cache-dir"
        "/state/${remote.name}/cache"
        "--log-level"
        "INFO"
      ]
      ++ lib.optionals (job.command == "sync") [ "--delete-during" ]
      ++ concatMap (exclude: [
        "--exclude"
        exclude
      ]) job.excludes
      ++ job.extraArgs;
      cleanupArgs = [
        "delete"
        "${remote.remote}:_versions/${job.destination}"
        "--config"
        "/state/${remote.name}/rclone.conf"
        "--min-age"
        "30d"
        "--log-level"
        "INFO"
      ];
      retentionCleanupArgs = [
        "delete"
        "${remote.remote}:${job.destination}"
        "--config"
        "/state/${remote.name}/rclone.conf"
        "--min-age"
        job.retention
        "--log-level"
        "INFO"
      ];
    in
    ''
      set -eu
      timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
      ${lib.optionalString job.versioned ''rclone mkdir ${escapeShellArgs [ "${remote.remote}:_versions/${job.destination}" ]} --config ${escapeShellArgs [ "/state/${remote.name}/rclone.conf" ]}''}
      rclone ${escapeShellArgs commonArgs} ${lib.optionalString job.versioned ''--backup-dir "${remote.remote}:_versions/${job.destination}/$timestamp"''}
      ${lib.optionalString job.versioned "rclone ${escapeShellArgs cleanupArgs}"}
      ${lib.optionalString (job.retention != null) "rclone ${escapeShellArgs retentionCleanupArgs}"}
    '';

  mkContainer = job: remote: {
    name = remote.name;
    inherit image;
    command = [
      "/bin/sh"
      "-c"
    ];
    args = [ (mkScript job remote) ];
    env = job.env;
    volumeMounts = job.volumeMounts ++ [
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
  };

  mkManifest = job: {
    apiVersion = "batch/v1";
    kind = "CronJob";
    metadata = {
      name = "rclone-backup";
      namespace = job.namespace;
    };
    spec = {
      inherit (job) schedule;
      concurrencyPolicy = "Forbid";
      successfulJobsHistoryLimit = 3;
      failedJobsHistoryLimit = 3;
      jobTemplate.spec.template = {
        metadata.annotations."reloader.stakater.com/auto" = "true";
        spec = {
          restartPolicy = "OnFailure";
          volumes = job.volumes ++ [
            {
              name = "config-ro";
              secret.secretName = "rclone-config";
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
              args = [
                "set -eu; for remote in ${remoteNames}; do mkdir -p /state/$remote/cache; cp /config-ro/rclone.conf /state/$remote/rclone.conf; done"
              ];
              volumeMounts = [
                {
                  name = "config-ro";
                  mountPath = "/config-ro";
                  readOnly = true;
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
          containers = map (mkContainer job) remotes;
        };
      };
    };
  };
in
{
  options.homelab.rcloneBackups = {
    enable = mkEnableOption "rclone backups" // {
      default = true;
    };
    yandex.enable = mkEnableOption "Yandex Disk backup destination" // {
      default = true;
    };
    mega.enable = mkEnableOption "MEGA backup destination";
    jobs = mkOption {
      default = { };
      type = types.attrsOf (
        types.submodule (
          { name, ... }: {
            options = {
              enable = mkEnableOption "the ${name} backup" // {
                default = true;
              };
              namespace = mkOption { type = types.str; };
              schedule = mkOption { type = types.str; };
              source = mkOption { type = types.str; };
              command = mkOption {
                type = types.enum [
                  "sync"
                  "copy"
                ];
                default = "sync";
              };
              destination = mkOption {
                type = types.str;
                default = name;
              };
              versioned = mkOption {
                type = types.bool;
                default = true;
              };
              retention = mkOption {
                type = types.nullOr types.str;
                default = null;
              };
              excludes = mkOption {
                type = types.listOf types.str;
                default = [ ];
              };
              extraArgs = mkOption {
                type = types.listOf types.str;
                default = [ ];
              };
              volumes = mkOption {
                type = types.listOf types.attrs;
                default = [ ];
              };
              volumeMounts = mkOption {
                type = types.listOf types.attrs;
                default = [ ];
              };
              env = mkOption {
                type = types.listOf types.attrs;
                default = [ ];
              };
            };
          }
        )
      );
    };
  };

  config = mkIf (cfg.enable && remotes != [ ]) {
    sops.secrets.rcloneConfigB64 = { };
    sops.templates = mapAttrs' (
      name: job:
      nameValuePair "${name}-rclone-config" {
        content = builtins.toJSON {
          apiVersion = "v1";
          kind = "Secret";
          metadata = {
            name = "rclone-config";
            namespace = job.namespace;
          };
          data."rclone.conf" = config.sops.placeholder.rcloneConfigB64;
        };
        path = "/var/lib/rancher/k3s/server/manifests/${name}-rclone-config.json";
      }
    ) enabledJobs;
    services.k3s.manifests = mapAttrs' (
      name: job: nameValuePair "${name}-rclone-backup" { content = mkManifest job; }
    ) enabledJobs;
  };
}
