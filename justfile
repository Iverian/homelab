flake := ".#homelab"
node := "iverian@homelab.lan"
rebuild_cmd := "nix run nixpkgs#nixos-rebuild -- --sudo --use-substitutes --build-host " + node + " --target-host " + node + " --flake " + flake

help:
  @just --list

# Update host dependencies
update:
  nix flake update
  nix flake lock

# Apply host configuration
apply:
  nix flake lock
  {{ rebuild_cmd }} switch

# Dry run
plan:
  nix flake lock
  {{ rebuild_cmd }} dry-activate
