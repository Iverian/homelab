default_node := "homelab"

help:
  @just --list

# Update host dependencies
update:
  nix flake update
  nix flake lock

rebuild NODE *ARGS:
  addr="iverian@{{ NODE }}.lan" flake=".#{{ NODE }}" && nix run nixpkgs#nixos-rebuild -- --use-substitutes --sudo --target-host "$addr" --flake "$flake" {{ ARGS }}

# Apply host configuration
apply NODE=default_node *ARGS:
  @just rebuild {{ NODE }} switch {{ ARGS }}

# Apply host configuration
on-boot NODE=default_node *ARGS:
  @just rebuild {{ NODE }} boot {{ ARGS }}

# Dry run
plan NODE=default_node *ARGS:
  @just rebuild {{ NODE }} dry-activate {{ ARGS }}

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
