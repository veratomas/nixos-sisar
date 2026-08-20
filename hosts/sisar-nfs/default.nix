{
  config,
  pkgs,
  lib,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/base.nix
    ../../modules/nfs-server.nix

    # Único host con entorno gráfico: se usa como terminal de trabajo.
    ../../modules/plasma6.nix
    ../../modules/rustdesk.nix
  ];

  networking.hostName = "sisar-nfs";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  system.stateVersion = "25.11";
}
