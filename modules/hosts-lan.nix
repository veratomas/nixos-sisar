# modules/hosts-lan.nix
#
# Direccionamiento estático de la LAN + resolución de nombres entre hosts.
#
# ┌──────────────────────────────────────────────────────────────────────┐
# │ gateway / nameservers / searchDomains: verificados contra el DHCP de │
# │ la red icediac (host sin config estática, antes de aplicar).         │
# │ Si la red cambia, re-verificar en un equipo con internet:            │
# │   ip route | grep default        -> el gateway real                  │
# │   cat /etc/resolv.conf           -> nameserver y search              │
# │   ip -br link                    -> el nombre de la placa            │
# └──────────────────────────────────────────────────────────────────────┘
{
  config,
  lib,
  ...
}:
let
  lan = {
    sisar-nfs = "192.168.0.241";
    sisar1 = "192.168.0.242";
    sisar2 = "192.168.0.243";
    sisar3 = "192.168.0.244";
    sisar4 = "192.168.0.245";
    # sisar5    = "192.168.0.246";
  };

  # Verificado contra el DHCP de la red (icediac): el gateway es .240, NO .1.
  gateway = "192.168.0.240";

  # El mismo equipo hace de gateway y de DNS en esta red. Los públicos quedan
  # como respaldo; van SEGUNDO porque sólo .240 resuelve los nombres internos.
  nameservers = [
    gateway
    "1.1.1.1"
    "8.8.8.8"
  ];

  # Dominio de búsqueda de la red (el DHCP entrega "search icediac").
  searchDomains = [ "icediac" ];

  iface = "enp3s0"; # <-- VERIFICAR con: ip -br link
  prefix = "24";

  myIp = lan.${config.networking.hostName};

  # Formato keyfile de NetworkManager: lista separada y terminada en ";"
  toNmList = lib.concatMapStrings (s: "${s};");
in
{
  # Resolución de nombres entre hosts (tabla inversa: IP -> [nombres])
  networking.hosts = lib.mapAttrs' (n: ip: lib.nameValuePair ip [ n ]) lan;

  # Red de seguridad: deja los nameservers también en /etc/resolv.conf vía
  # resolvconf, independientemente de lo que resuelva NetworkManager.
  networking.nameservers = nameservers;
  networking.search = searchDomains;

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
      address1 = "${myIp}/${prefix},${gateway}";
      dns = toNmList nameservers;
      dns-search = toNmList searchDomains;
      ignore-auto-dns = "true";
    };
    ipv6.method = "disabled";
  };
}
