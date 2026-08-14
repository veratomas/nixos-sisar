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
    ../../modules/nfs-client.nix
  ];

  networking.hostName = "sisar3";

  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda"; # verificar el disco real de este equipo
  boot.loader.grub.useOSProber = true;

  system.stateVersion = "25.11";
}
