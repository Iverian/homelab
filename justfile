flake := ".#homelab"
node := "iverian@homelab.lan"
rebuild_cmd := "nix run nixpkgs#nixos-rebuild -- --verbose --use-substitutes --sudo --build-host " + node + " --target-host " + node + " --flake " + flake

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

[no-cd]
decrypt FILE:
  sops --decrypt --indent 2 --in-place "{{ FILE }}"

[no-cd]
encrypt FILE:
  sops --encrypt --indent 2 --in-place "{{ FILE }}"
