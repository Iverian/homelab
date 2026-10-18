# AGENTS.md

This file provides guidance to agents when working with code in this repository.

## Commands

All workflows go through `just` (see [justfile](justfile)):

```bash
just apply           # Deploy configuration to the node (nixos-rebuild switch)
just apply-on-reboot # Apply on next reboot (nixos-rebuild boot)
just plan            # Dry run — shows what would change
just update          # Update all flake inputs (nix flake update + lock)
just decrypt FILE    # Decrypt a SOPS-encrypted file in-place
just encrypt FILE    # Encrypt a file in-place with SOPS
```

The target node is `iverian@homelab.lan`. Commands use `--build-host` and `--target-host` so builds happen on the node itself, not locally.

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

### Storage

- **System disk**: NVMe (Samsung 970 EVO 250GB), ext4 on LUKS, USB key for LUKS unlock
- **Data pool** (`zdata`): 4× HDD in two ZFS mirrors (2×4TB + 2×2TB), encrypted
  - `/data/hdd` → StorageClass `storage` (for k8s PVCs on spinning disk)
  - `/data/ssd` → StorageClass `local-path` (default, for k8s PVCs on NVMe)

### Networking / Ingress

- **MetalLB** allocates IPs `192.168.90.90–100`; the main gateway listens on `.90`
- **Envoy Gateway** is the ingress controller (Traefik is explicitly disabled)
  - Gateway `main` in namespace `envoy-gateway-system`; two hostnames: `*.iverian.ru` (public) and `*.home.iverian.ru` (private, TLS terminated)
  - HTTP → HTTPS redirect is handled by an HTTPRoute in the same namespace
- **cert-manager** issues TLS via Let's Encrypt with Cloudflare DNS-01
- **Authelia** provides SSO/OIDC; Grafana is pre-configured as an OIDC client

### Adding a new service

1. Create `node/k8s/<service>.nix`
2. Import it in [node/main.nix](node/main.nix) under the `imports` list
3. Declare any needed secrets in `sops.secrets` and reference them via `sops.templates` if they need to become K8s Secrets
4. Add the Helm chart via `services.k3s.autoDeployCharts` and/or raw manifests via `services.k3s.manifests`
