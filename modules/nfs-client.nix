# Cliente NFS (hosts: sisar1..sisar5)
#
# Monta lo que exporta sisar-nfs. Se usa automount de systemd: el montaje se
# hace al primer acceso y el arranque no queda bloqueado si el servidor
# todavía no está disponible.
{
  config,
  pkgs,
  lib,
  ...
}:
let
  server = "sisar-nfs";

  mountOpts = [
    "nfsvers=4.2"
    "_netdev"
    "soft"
    "timeo=100"
    "retrans=3"
    "noatime"
    "x-systemd.automount"
    "x-systemd.idle-timeout=600"
    "noauto"
  ];
in
{
  boot.supportedFilesystems = [ "nfs" ];
  services.rpcbind.enable = true;

  fileSystems."/mnt/sisar/datos" = {
    device = "${server}:/datos";
    fsType = "nfs4";
    options = mountOpts;
  };

  fileSystems."/mnt/sisar/home" = {
    device = "${server}:/home";
    fsType = "nfs4";
    options = mountOpts;
  };

  # Debe coincidir con el dominio del servidor o los usuarios aparecen como nobody.
  services.nfs.idmapd.settings = {
    General.Domain = "sisar.lan";
  };

  environment.systemPackages = with pkgs; [ nfs-utils ];
}
