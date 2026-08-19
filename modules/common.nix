{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
{
  environment.systemPackages = with pkgs; [
    git
    rust-analyzer
    uv
    nil
    ruff
    ty
    nixfmt-rfc-style
  ];

  # Sin fuentes de escritorio acá; las agrega plasma6.nix en el host gráfico.

  # Make sure the system uses flakes
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Documentación de escritorio innecesaria en un servidor headless.
  # mkDefault para que el host con Plasma (sisar-nfs) pueda reactivarla.
  documentation.doc.enable = lib.mkDefault false;
  documentation.nixos.enable = lib.mkDefault false;

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  nix.optimise = {
    automatic = true;
    dates = [ "weekly" ];
  };
}
