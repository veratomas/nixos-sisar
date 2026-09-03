# Export/mount P2P de jobs/ entre nodos de cómputo (sisar1..sisar4).
#
# Separado a propósito del NFS centralizado de sisar-server (ver
# nfs-server.nix / nfs-client.nix): archive/ y logs/ siguen viviendo en el
# árbol único de sisar-server, pero jobs/ ahora es local a cada nodo y se
# comparte punto a punto.
#
# Cada nodo:
#   - exporta su propio /srv/<hostName>/jobs/ a los demás nodos de cómputo
#   - monta el jobs/ de cada peer bajo /mnt/peers/<peer>/jobs/
#
# Path distinto de /srv/sisar (que ya ocupa el mountpoint del export central
# de sisar-server) para que no colisionen.
#
# La lista de nodos y sus IPs se repite acá en vez de importarse de
# flake.nix — mismo criterio que hosts-lan.nix (los módulos no reciben la
# `lan` del flake por specialArgs). Si se agrega o saca un nodo de cómputo,
# hay que tocar ACÁ, hosts-lan.nix Y flake.nix.
#
# Nota: a diferencia de sisar-server (disco XFS dedicado, ver
# disco-sisar.nix), estos nodos no tienen todavía un disco de datos propio
# declarado — /srv/<hostName>/jobs/ se crea donde esté /srv, hoy el disco de
# sistema. Si se agrega un disco dedicado por nodo, este módulo no necesita
# cambios: sólo hace falta que el fileSystems de ese disco monte antes (ver
# RequiresMountsFor más abajo).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Nodos que participan del P2P de jobs. sisar5 queda comentado hasta que
  # se habilite en flake.nix (ver hostNames ahí) y en hosts-lan.nix.
  lan = {
    sisar1 = "192.168.0.242";
    sisar2 = "192.168.0.243";
    sisar3 = "192.168.0.244";
    sisar4 = "192.168.0.245";
    # sisar5 = "192.168.0.246";
  };

  self = config.networking.hostName;
  peers = lib.filterAttrs (name: _: name != self) lan;

  jobsDir = "/srv/${self}/jobs";
  lanCidr = "192.168.0.0/24";

  # Mismo criterio que nfs-server.nix: async por rendimiento, aceptable
  # porque un job es reprocesable si el nodo se cae a mitad de una escritura.
  exportOpts = "rw,async,no_subtree_check,root_squash";

  # Mismas opciones de montaje que nfs-client.nix (hard: los runners escriben
  # resultados pesados y no queremos archivos truncados por un timeout).
  mountOpts = [
    "nfsvers=4.2"
    "_netdev"
    "hard"
    "timeo=600"
    "retrans=2"
    "rsize=1048576"
    "wsize=1048576"
    "noatime"
    "x-systemd.automount"
    "noauto"
  ];
in
{
  assertions = [
    {
      assertion = lib.hasAttr self lan;
      message = ''
        nfs-jobs-p2p.nix: el host '${self}' no está en la lista de nodos
        P2P (variable `lan` de este módulo). Agregalo ahí, o no importes
        este módulo desde hosts/${self}/default.nix.
      '';
    }
  ];

  boot.supportedFilesystems = [ "nfs" ];

  # Directorio local que este nodo exporta a sus peers.
  systemd.tmpfiles.rules = [
    "d ${jobsDir} 2775 sisar sisar-data -"
  ];

  systemd.services.nfs-server = {
    after = [ "systemd-tmpfiles-setup.service" ];
    unitConfig.RequiresMountsFor = jobsDir;
  };

  services.nfs.server = {
    enable = true;
    # Puertos distintos a los 4000-4002 de sisar-server: no colisionan entre
    # sí (son hosts distintos), pero así se distinguen a simple vista en
    # firewall/logs cuál NFS es cuál.
    lockdPort = 4011;
    mountdPort = 4012;
    statdPort = 4010;

    exports = ''
      ${jobsDir}  ${lanCidr}(${exportOpts},fsid=0)
    '';
  };

  # Monta el jobs/ de cada peer bajo /mnt/peers/<peer>/jobs.
  fileSystems = lib.mapAttrs' (
    peer: _:
    lib.nameValuePair "/mnt/peers/${peer}/jobs" {
      device = "${peer}:/";
      fsType = "nfs4";
      options = mountOpts;
    }
  ) peers;

  networking.firewall = {
    allowedTCPPorts = [
      111 # rpcbind
      2049 # nfsd
      4010 # statd
      4011 # lockd
      4012 # mountd
    ];
    allowedUDPPorts = [
      111
      4010
      4011
      4012
    ];
  };
}
