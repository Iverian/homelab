node_flake := ".#homelab"
external_flake := ".#external"
image_flake := ".#image"

node := "iverian@homelab.lan"
rebuild_cmd := "nix run nixpkgs#nixos-rebuild -- --use-substitutes --sudo --build-host " + node + " --target-host " + node + " --flake " + node_flake
rebuild_external_cmd := "nix run nixpkgs#nixos-rebuild -- --flake " + external_flake
rebuild_image_cmd := "nix run nixpkgs#nixos-rebuild -- --flake " + image_flake

help:
  @just --list

# Update host dependencies
update:
  nix flake update
  nix flake lock

# Apply host configuration
apply:
  {{ rebuild_cmd }} switch

# Apply host configuration
apply-on-reboot:
  {{ rebuild_cmd }} boot

# Dry run
plan:
  {{ rebuild_cmd }} dry-activate

image *ARGS:
  {{ rebuild_image_cmd }} build-image --image-variant openstack {{ ARGS }}

[no-cd]
decrypt FILE:
  sops --decrypt --indent 2 --in-place "{{ FILE }}"

[no-cd]
encrypt FILE:
  sops --encrypt --indent 2 --in-place "{{ FILE }}"

cert *ARGS:
  poetry run "./script/cert.py" -- {{ ARGS }}
