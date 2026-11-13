# AGENTS.md

This file provides guidance to agents when working with code in this repository.

## IP addresses

Do not write literal IP addresses into files tracked by Git or intended to be committed, including configuration, scripts, documentation, and examples. Use DNS names instead. If a setting requires an IP address, obtain it at runtime or from configuration outside Git; do not hardcode it in the repository.

## Commands

All workflows go through `just` (see [justfile](justfile)):

```bash
just apply                    # Build/import local images, then nixos-rebuild switch
just on-boot                  # Build/import local images, then nixos-rebuild boot
just plan                     # Remote dry-activate
just service-images           # Build/import every services/*/manifest.json
just service-image MANIFEST   # Build/import one local service image
just service-images-test      # Test manifest parsing and content-addressed tags
just trusted-ip-test          # Exercise trusted-ip in its deployment image
just trusted-ip-integration   # Test real Envoy trusted-IP/rate-limit behavior
just update                   # Update all flake inputs
just decrypt FILE             # Decrypt a SOPS file in place
just encrypt FILE             # Encrypt a SOPS file in place
```

The default target is `iverian@homelab.lan`. Nix builds use the node as both
`--build-host` and `--target-host`. Service container images are built locally
and imported into the node's k3s/containerd before `switch` or `boot`.

To check the flake without deploying: `nix flake check`

## Verifying changes

Verification is part of every change. Do not treat a successful `just apply` as proof that Kubernetes accepted or reconciled the new configuration.

### Before deployment

1. Inspect `git status --short` and the relevant diff. Preserve unrelated staged and unstaged user changes.
2. Run `nix flake check` for every Nix change.
3. Use `just plan` when the scope or activation effects are unclear.
4. Never print decrypted secrets, Kubernetes Secret data, tokens, or complete rendered secret manifests. Compare secret files using hashes or `cmp` instead.

### Deployment

Apply the configuration with:

```bash
just apply
```

Wait for the command to finish and check the complete activation output. A build succeeding while activation or a later k3s reconciliation fails is not a successful deployment.

### Kubernetes verification

Always run `kubectl` locally using the configured `homelab` context. Do not SSH to the node to run `kubectl` there.

Start with broad health checks, then inspect only the affected namespaces and resources:

```bash
kubectl config current-context
kubectl get nodes
kubectl get pods -A
kubectl get events -A --field-selector type=Warning --sort-by=.lastTimestamp
kubectl -n <namespace> get deploy,statefulset,cronjob,job,pod
kubectl -n <namespace> rollout status deployment/<name> --timeout=5m
kubectl -n <namespace> rollout status statefulset/<name> --timeout=5m
kubectl -n <namespace> logs <pod> -c <container> --tail=200
```

Verify the live resource content, not only its existence. Check image tags, container names, arguments, environment references, volumes, PVC names, schedules, and readiness. k3s AddOn reconciliation can be asynchronous, so repeat the live check after a short delay when the generated manifest has changed but the resource is still stale.

For resources managed by the k3s manifest controller, inspect the corresponding AddOn locally:

```bash
kubectl -n kube-system get addon <manifest-name> -o yaml
kubectl -n kube-system describe addon <manifest-name>
```

Use SSH only for host-level evidence unavailable through the Kubernetes API, especially rendered manifests and k3s logs:

```bash
ssh iverian@homelab.lan 'sudo ls -l /var/lib/rancher/k3s/server/manifests/'
ssh iverian@homelab.lan 'sudo journalctl -u k3s --since "15 minutes ago" --no-pager'
```

Do not display rendered manifests that contain secrets. Inspect their metadata, hashes, permissions, or non-secret fields instead.

### Backup verification

Confirm both the producer and uploader sides:

1. Check that logical database backup Jobs complete and that the staging StatefulSet/PVC is healthy.
2. Check the live backup CronJob specification, including all expected remote containers, source PVCs, exclusions, and retention arguments.
3. Remove only obsolete test or pre-fix Jobs that are actively blocking a new run through `concurrencyPolicy: Forbid`.
4. When the requested work authorizes a real backup test, create a Job from the live CronJob rather than assembling a different command:

   ```bash
   kubectl -n <namespace> create job --from=cronjob/rclone-backup backup-verify-<timestamp>
   kubectl -n <namespace> wait --for=condition=complete job/backup-verify-<timestamp> --timeout=10m
   ```

5. Inspect logs and terminated exit codes for every remote container independently. A multi-container Job is successful only when every uploader exits with code 0.
6. For authentication-only checks, prefer read-only commands such as `rclone lsd <remote>:`. Do not infer that a successful listing proves uploads work; a real write test is needed when end-to-end verification is required and authorized.
7. Verify exclusions against both transfer logs and remote directory listings. New excludes do not delete data uploaded by older configurations.

### Completion criteria

A change is complete only when:

- local evaluation/checks pass;
- deployment and activation finish successfully;
- live Kubernetes resources match the intended configuration;
- affected workloads become Ready or Jobs complete successfully;
- relevant logs contain no new errors;
- any remaining warnings, stale data, or follow-up work are explicitly reported.

## Architecture

### Structure

```
flake.nix              # Single output: nixosConfigurations.homelab
node/
  main.nix             # Top-level NixOS config (boot, networking, k3s, users)
  hardware-configuration.nix
  disko-config.nix     # Disk layout definition
  k8s/                 # Kubernetes workloads as NixOS modules
main.sops.yaml         # Encrypted secrets (age)
services/              # Locally built service images and manifest.json files
script/
  service_images.py    # Generic content-addressed image builder/importer
```

### How Kubernetes workloads are declared

All K8s services are NixOS modules under `node/k8s/`. They use two patterns:

**Helm charts** via `services.k3s.autoDeployCharts.<name>`:
```nix
services.k3s.autoDeployCharts.cert-manager = {
  repo = "oci://...";
  version = "1.19.2";
  hash = "sha256-...";
  targetNamespace = "cert-manager";
  createNamespace = true;
  values = { ... };  # Helm values as Nix attrset
};
```

**Raw manifests** via `services.k3s.manifests.<name>.content` (Nix attrset → JSON) or `.source` (file path). Manifests land in `/var/lib/rancher/k3s/server/manifests/`.

### Secrets management

Secrets are encrypted in [main.sops.yaml](main.sops.yaml) using `age`. The node decrypts them at boot using the key at `/etc/nixos/secrets/sops.key`.

Each k8s module declares which secrets it needs:
```nix
sops.secrets.cloudflareApiKey = { };
```

To inject secrets into K8s resources, use `sops.templates`:
```nix
sops.templates.cloudflare-api-key = {
  content = builtins.toJSON { ... stringData.key = config.sops.placeholder.cloudflareApiKey; };
  path = "/var/lib/rancher/k3s/server/manifests/cloudflare-api-key.json";
};
```

This writes a rendered manifest with plaintext secrets directly into the k3s auto-deploy directory.

Rendered secret manifests must never be printed or copied into Git. When a
SOPS template is written into the k3s manifest directory and changes must be
noticed immediately, set `restartUnits = [ "k3s.service" ];`. The rendered
files are symlinks, so relying only on the k3s file watcher can leave a live
resource stale after the symlink target changes.

Workloads that consume ConfigMaps or Secrets must use explicit Stakater
Reloader annotations. Use the named-resource annotations when possible:

```nix
metadata.annotations = {
  "configmap.reloader.stakater.com/reload" = "service-config";
  "secret.reloader.stakater.com/reload" = "service-secrets";
};
```

### Local service images

Local images live under `services/<service>/` and are described by a minimal
`manifest.json`:

```json
{
  "image": "localhost/homelab/example",
  "hashFiles": ["requirements.txt"]
}
```

The Dockerfile is always included in the content hash and must not be repeated
in `hashFiles`. The first 20 hexadecimal characters of the SHA-256 digest form
the immutable tag. Nix modules must calculate the tag from the same manifest
and files, and local deployments use `imagePullPolicy = "Never"`.

Prefer Debian/glibc bases for locally maintained images. Do not introduce
Alpine/musl images unless the user explicitly approves an exception.

### Storage

- **System disk**: NVMe (Samsung 970 EVO 250GB), ext4 on LUKS, USB key for LUKS unlock
- **Data pool** (`zdata`): 4× HDD in two ZFS mirrors (2×4TB + 2×2TB), encrypted
  - `/data/hdd` → StorageClass `storage` (for k8s PVCs on spinning disk)
  - `/data/ssd` → StorageClass `local-path` (default, for k8s PVCs on NVMe)

### Networking / Ingress

- **MetalLB** allocates addresses from the private LAN pool
- **Envoy Gateway** is the ingress controller (Traefik is explicitly disabled)
  - Gateway `main` is the direct/internal entry point on standard HTTP/HTTPS ports
  - Gateway `external` is the FRP-facing entry point, requires Proxy Protocol, and listens on the public HTTP/HTTPS ports
  - Public services use `*.iverian.ru`; the former `*.home.iverian.ru` wildcard is not used
  - Both gateways terminate TLS with the same `*.iverian.ru` certificate; HTTPRoute attachment controls whether a service is internal, external, or both
  - HTTP → HTTPS redirect is handled by an HTTPRoute in the same namespace
- The `external` HTTPS listener is protected by the `trusted-ip` gRPC ext-auth service and global rate limiting backed by Valkey
- `trusted-ip` classifies clients using Authelia and preserves state in `trusted-ip-store`; enforcement is enabled through `homelab.trustedIP.enforce`
- **cert-manager** issues TLS via Let's Encrypt with Cloudflare DNS-01
- **Authelia** provides SSO/OIDC for services that support native OIDC

### Deployed applications

The current user-facing workloads are:

- `home.iverian.ru`: Homepage dashboard
- `auth.iverian.ru`: Authelia
- `nextcloud.iverian.ru`: Nextcloud
- `gitea.iverian.ru`: Gitea
- `home-assistant.iverian.ru`: Home Assistant
- `jellyfin.iverian.ru`: Jellyfin
- `transmission.iverian.ru`: Transmission
- `foundry.iverian.ru`: Foundry VTT
- `rpg-cards.iverian.ru`: RPG card generator
- `sync.iverian.ru`: CouchDB sync endpoint

Supporting workloads include CloudNativePG databases and logical backups,
Valkey, Garage object storage, rclone backups, Samba, Tailscale, DNS proxy,
Intel GPU/NFD, cert-manager, Reloader, Envoy Gateway, MetalLB, FRP client, and
the storage operators. Netdata is intentionally not deployed.

### Homepage

Homepage is configured entirely through the `homepage-config` ConfigMap in
`node/k8s/home.nix`. It uses Russian UI text, cluster-mode Kubernetes metrics,
native Nextcloud and Transmission widgets, and health/Kubernetes cards for the
other services. Do not make dashboard changes through the UI.

Homepage authenticates through its native OIDC integration with Authelia. Do
not add an Envoy `SecurityPolicy`/forward-auth layer in front of Homepage.

### Adding a new service

1. Create `node/k8s/<service>.nix`
2. Import it in [node/main.nix](node/main.nix) under the `imports` list
3. Declare any needed secrets in `sops.secrets` and reference them via `sops.templates` if they need to become K8s Secrets
4. Add the Helm chart via `services.k3s.autoDeployCharts` and/or raw manifests via `services.k3s.manifests`
5. Add Reloader annotations for every consumed ConfigMap or Secret
6. If the service needs a local image, add `services/<service>/manifest.json`, use a Debian/glibc Dockerfile, and derive the exact same content-addressed tag in Nix
7. Attach routes deliberately to `main`, `external`, or both; all public names belong under `*.iverian.ru`
