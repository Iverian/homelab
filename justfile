default_node := "homelab"

help:
  @just --list

# Apply Debian external host hardening; retain public SSH until Tailscale is verified.
external-apply STAGE="--services-only":
  python3 script/external-apply.py {{ STAGE }}

# Update host dependencies
update:
  nix flake update
  nix flake lock

rebuild NODE *ARGS:
  @python3 script/check-encrypted-secrets.py
  addr="iverian@{{ NODE }}.lan" flake=".#{{ NODE }}" && nix run nixpkgs#nixos-rebuild -- --use-substitutes --sudo --build-host "$addr" --target-host "$addr" --flake "$flake" {{ ARGS }}

# Apply host configuration
apply NODE=default_node *ARGS: (service-images NODE)
  @just rebuild {{ NODE }} switch {{ ARGS }}

# Apply host configuration
on-boot NODE=default_node *ARGS: (service-images NODE)
  @just rebuild {{ NODE }} boot {{ ARGS }}

# Dry run
plan NODE=default_node *ARGS:
  @just rebuild {{ NODE }} dry-activate {{ ARGS }}

# Build every services/*/manifest.json and import missing images into the node.
service-images NODE=default_node *ARGS:
  python3 script/service_images.py --all --node {{ NODE }} {{ ARGS }}

# Build one service image and import it into the node.
service-image MANIFEST NODE=default_node *ARGS:
  python3 script/service_images.py --node {{ NODE }} {{ ARGS }} "{{ MANIFEST }}"

# Compatibility target for the trusted-IP image.
trusted-ip-image NODE=default_node:
  python3 script/service_images.py --node {{ NODE }} services/trusted-ip/manifest.json

# Exercise the service using the exact deployment image, without accessing the node.
trusted-ip-test:
  python3 script/service_images.py --no-upload --run --run-network none --run-env AUTH_HOST=auth.example.test --run-volume .:/app:ro services/trusted-ip/manifest.json -- python -m unittest -v

# Unit tests for service image manifest parsing and hashing.
service-images-test:
  python3 script/test_service_images.py

# Create temporary probe routes on external, test real Envoy limits, then remove them.
trusted-ip-integration:
  python3 services/trusted-ip/integration.py

# Build base external VM image
image *ARGS:
  nix run nixpkgs#nixos-rebuild -- --flake .#image build-image --image-variant openstack {{ ARGS }}

# Regenerate Cert
cert *ARGS:
  poetry run "./script/cert.py" -- {{ ARGS }}

[no-cd]
decrypt FILE:
  sops --decrypt --indent 2 --in-place "{{ FILE }}"

[no-cd]
encrypt FILE:
  sops --encrypt --indent 2 --in-place "{{ FILE }}"
