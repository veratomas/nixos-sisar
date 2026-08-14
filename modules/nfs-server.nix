# Servidor NFS (host: sisar-nfs)
#
# Se usa NFSv4: /srv/sisar es la raíz virtual del export (fsid=0) y debajo
# cuelgan los directorios compartidos. Por eso los clientes montan
# "sisar-nfs:/datos" y NO "sisar-nfs:/srv/sisar/datos".
{
  config,
  pkgs,
  lib,
  ...
}:
let
  # Red local autorizada a montar. Ajustar si tu LAN es otra.
  lanCidr = "192.168.1.0/24";

  # Opciones comunes de exportación.
  opts = "rw,sync,no_subtree_check,root_squash";
in
{
  # Directorios compartidos. El setgid (2775) en datos hace que todo lo que se
  # cree ahí quede en el grupo sisar-data y sea escribible por el equipo.
  systemd.tmpfiles.rules = [
    "d /srv/sisar        0755 root  root       -"
    "d /srv/sisar/datos  2775 sisar sisar-data -"
    "d /srv/sisar/home   2775 sisar sisar-data -"
  ];

  systemd.services.nfs-server.after = [ "systemd-tmpfiles-setup.service" ];

  services.nfs.server = {
    enable = true;
    # Puertos fijos, para poder abrirlos en el firewall de forma determinista.
    lockdPort = 4001;
    mountdPort = 4002;
    statdPort = 4000;

    exports = ''
      /srv/sisar        ${lanCidr}(${opts},fsid=0,crossmnt)
      /srv/sisar/datos  ${lanCidr}(${opts})
      /srv/sisar/home   ${lanCidr}(${opts})
    '';
  };

  # Dominio idmap: debe coincidir en servidor y clientes (ver nfs-client.nix).
  services.nfs.idmapd.settings = {
    General.Domain = "sisar.lan";
  };

  networking.firewall = {
    allowedTCPPorts = [
      111 # rpcbind
      2049 # nfsd
      4000 # statd
      4001 # lockd
      4002 # mountd
    ];
    allowedUDPPorts = [
      111
      4000
      4001
      4002
    ];
  };
}
