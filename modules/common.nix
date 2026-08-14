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

  # Sin entorno gráfico: no se instalan fuentes de escritorio.

  # Make sure the system uses flakes
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Documentación de escritorio innecesaria en un servidor headless
  documentation.doc.enable = false;
  documentation.nixos.enable = false;

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
