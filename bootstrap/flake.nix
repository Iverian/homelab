{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    disko.url = "github:nix-community/disko/v1.12.0";
    disko.inputs.nixpkgs.follows = "nixpkgs";
  };
  outputs = { self, disko, nixpkgs, ... }: {
    nixosConfigurations.homelab = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        {
          nix = {
            settings.experimental-features = [ "nix-command" "flakes" ];
          };
        }
        disko.nixosModules.disko
        ./configuration.nix
      ];
    };
  };
}
