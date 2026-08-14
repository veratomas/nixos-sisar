# Resolución de nombres en la red local.
#
# IMPORTANTE: ajustá las IPs a las de tu red antes de desplegar.
# Idealmente reservá estas IPs por DHCP (reserva por MAC) en el router.
{
  config,
  pkgs,
  lib,
  ...
}:
let
  lan = {
    "192.168.1.10" = [ "sisar-nfs" ];
    "192.168.1.11" = [ "sisar1" ];
    "192.168.1.12" = [ "sisar2" ];
    "192.168.1.13" = [ "sisar3" ];
    "192.168.1.14" = [ "sisar4" ];
    "192.168.1.15" = [ "sisar5" ];
  };
in
{
  networking.hosts = lan;

  # mDNS (nombre.local) como respaldo si las IPs cambian.
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
    };
  };
}
