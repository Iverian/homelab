# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

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

- **MetalLB** allocates IPs `192.168.88.90–100`; the main gateway listens on `.90`
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
