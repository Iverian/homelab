{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    disko.url = "github:nix-community/disko/v1.12.0";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  };
  outputs =
    {
      self,
      nixpkgs,
      disko,
      sops-nix,
      ...
    }:
    {
      nixosConfigurations = {
        external = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            {
              nix = {
                settings.experimental-features = [
                  "nix-command"
                  "flakes"
                ];
              };
            }
            sops-nix.nixosModules.sops
            ./external/main.nix
          ];
        };
        homelab = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            {
              nix = {
                settings.experimental-features = [
                  "nix-command"
                  "flakes"
                ];
              };
            }
            disko.nixosModules.disko
            sops-nix.nixosModules.sops
            ./node/main.nix
          ];
        };
      };
    };
}
