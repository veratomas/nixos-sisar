# modules/hosts-lan.nix
{ config, lib, ... }:
let
  lan = {
    sisar-nfs = "192.168.0.241";
    sisar1    = "192.168.0.242";
    sisar2    = "192.168.0.243";
    sisar3    = "192.168.0.244";
    sisar4    = "192.168.0.245";
    # sisar5    = "192.168.0.246";
  };

  gateway = "192.168.0.1";
  iface   = "enp3s0";                      # verificar con: ip -br link
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
