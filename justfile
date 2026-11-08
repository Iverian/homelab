default_node := "homelab"

help:
  @just --list

# Update host dependencies
update:
  nix flake update
  nix flake lock

rebuild NODE *ARGS:
  @python3 script/check-encrypted-secrets.py
  addr="iverian@{{ NODE }}.lan" flake=".#{{ NODE }}" && nix run nixpkgs#nixos-rebuild -- --use-substitutes --sudo --build-host "$addr" --target-host "$addr" --flake "$flake" {{ ARGS }}

# Apply host configuration
apply NODE=default_node *ARGS: (trusted-ip-image NODE)
  @just rebuild {{ NODE }} switch {{ ARGS }}

# Apply host configuration
on-boot NODE=default_node *ARGS: (trusted-ip-image NODE)
  @just rebuild {{ NODE }} boot {{ ARGS }}

# Dry run
plan NODE=default_node *ARGS:
  @just rebuild {{ NODE }} dry-activate {{ ARGS }}

# Build/test the Python dependency image and import it into the node's containerd.
trusted-ip-image NODE=default_node:
  python3 script/trusted-ip-image.py {{ NODE }}

# Exercise the service using the exact deployment image, without accessing the node.
trusted-ip-test:
  python3 script/trusted-ip-image.py --test-only

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
