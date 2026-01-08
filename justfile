help:
  @just --list

# Apply host configuration
apply:
  nix run nixpkgs#nixos-rebuild -- switch --sudo --use-substitutes --build-host iverian@homelab.lan --target-host iverian@homelab.lan --flake ./bootstrap#homelab
