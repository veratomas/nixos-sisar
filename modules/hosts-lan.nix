# modules/hosts-lan.nix
{ config, lib, ... }:
let
  lan = {
    sisar-nfs = "192.168.0.220";
    sisar1    = "192.168.0.221";
    sisar2    = "192.168.0.222";
    sisar3    = "192.168.0.223";
    sisar4    = "192.168.0.224";
    sisar5    = "192.168.0.225";
  };

  gateway = "192.168.1.1";
  iface   = "enp0s3";                      # verificar con: ip -br link
  myIp    = lan.${config.networking.hostName};
in
{
  # Resolución de nombres (tabla inversa: IP -> [nombres])
  networking.hosts = lib.mapAttrs' (n: ip: lib.nameValuePair ip [ n ]) lan;

  # Dirección propia de este host
  networking.networkmanager.ensureProfiles.profiles.lan = {
    connection = {
      id = "lan";
      type = "ethernet";
      interface-name = iface;
      autoconnect = true;
    };
    ipv4 = {
      method = "manual";
      address1 = "${myIp}/24,${gateway}";
      dns = gateway;
    };
    ipv6.method = "disabled";
  };
}
