{
  description = "SISAR cluster configuration (flake-based, headless)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    rust-overlay.url = "github:oxalica/rust-overlay";
  };

  outputs =
    {
      self,
      nixpkgs,
      ...
    }@inputs:
    let
      system = "x86_64-linux";

      # Módulo compartido por todos los hosts: habilita el overlay de rust-overlay
      overlaysModule = (
        { pkgs, ... }:
        {
          nixpkgs.overlays = [ inputs.rust-overlay.overlays.default ];
        }
      );

      mkHost =
        hostName:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit inputs;
          };
          modules = [
            overlaysModule
            ./hosts/${hostName}
          ];
        };
    in
    {
      nixosConfigurations = {
        sisar1 = mkHost "sisar1";
        sisar2 = mkHost "sisar2";
        sisar3 = mkHost "sisar3";
        sisar4 = mkHost "sisar4";
        sisar5 = mkHost "sisar5";
        sisar-nfs = mkHost "sisar-nfs";
      };
    };
}
