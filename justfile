node_flake := ".#homelab"
external_flake := ".#external"
node := "iverian@homelab.lan"
rebuild_cmd := "nix run nixpkgs#nixos-rebuild -- --use-substitutes --sudo --build-host " + node + " --target-host " + node + " --flake " + node_flake
rebuild_external_cmd := "nix run nixpkgs#nixos-rebuild -- --flake " + external_flake

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

external:
  {{ rebuild_external_cmd }} build-image --image-variant openstack

[no-cd]
decrypt FILE:
  sops --decrypt --indent 2 --in-place "{{ FILE }}"

[no-cd]
encrypt FILE:
  sops --encrypt --indent 2 --in-place "{{ FILE }}"
