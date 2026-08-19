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

  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda"; # verificar el disco real de este equipo
  boot.loader.grub.useOSProber = true;

  system.stateVersion = "25.11";
}
