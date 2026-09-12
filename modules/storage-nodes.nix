# Almacenamiento de jobs local al nodo, con un nombre único en todo el cluster.
#
# Reemplaza a nfs-jobs-p2p.nix. El árbol central de sisar-server (archive/,
# logs/, results/) no cambia: sigue montado en /srv/sisar por nfs-client.nix.
# Lo que cambia es jobs/, que pasa a vivir en el disco de cada nodo.
#
#   /srv/sisar-nodes/<nodo>/jobs/<uuid>     el MISMO path en los seis hosts
#
#       <nodo> == este host  -> bind mount del directorio real, local
#       <nodo> != este host  -> montaje NFSv4 del export de ese nodo
#
# ── Por qué el bind mount del propio directorio ──────────────────────────────
#
# El módulo anterior exportaba /srv/<host>/jobs y montaba a los demás en
# /mnt/peers/<peer>/jobs. Eso le da DOS nombres al mismo directorio: sisar1 veía
# sus jobs en /srv/sisar1/jobs y sisar2 los veía en /mnt/peers/sisar1/jobs.
#
# No es cosmético. job_spec.toml y los bind-mounts de Docker guardan rutas
# ABSOLUTAS, y el scheduler ordena las tareas reclamables comparando
# `jobs.work_dir` contra el prefijo de su propio root (claim_tasks, en
# shared/src/queries/task_claims.rs). Con dos nombres, un job armado en sisar1 y
# reclamado por sisar2 monta un path que allá no existe, y la preferencia de
# localidad deja de coincidir.
#
# El bind mount es lo que hace que el dueño use el mismo nombre que sus peers.
#
# ── El disco ────────────────────────────────────────────────────────────────
#
# `localRoot` es hoy un directorio del disco de sistema: los nodos todavía no
# tienen disco de datos propio. Cuando lo tengan, alcanza con un fileSystems
# que monte ese disco en `localRoot`; este módulo no cambia, porque ya declara
# RequiresMountsFor sobre él.
#
# Ojo mientras tanto: llenar el disco de sistema tira el nodo entero, no sólo
# el job. De ahí el piso de espacio libre que el scheduler chequea antes de
# reclamar el almacenamiento de un job.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  nodes = import ../nodes.nix;

  self = config.networking.hostName;
  peers = lib.filterAttrs (name: _: name != self) nodes.compute;

  # Directorio real en el disco de este nodo: lo que se exporta.
  localRoot = "/var/lib/sisar/jobs";

  # Espacio de nombres compartido: el mismo path en todos los hosts.
  sharedRoot = "/srv/sisar-nodes";
  selfMount = "${sharedRoot}/${self}/jobs";

  lanCidr = "192.168.0.0/24";

  # Mismo criterio que nfs-server.nix: async por rendimiento, aceptable porque
  # un job es reprocesable si el nodo se cae a mitad de una escritura.
  exportOpts = "rw,async,no_subtree_check,root_squash";

  # Mismas opciones que nfs-client.nix. `hard` y no `soft`: acá los runners
  # escriben resultados pesados, y con soft un timeout deja archivos truncados
  # que parecen completos.
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
      assertion = lib.hasAttr self nodes.compute;
      message = ''
        storage-nodes.nix: el host '${self}' no está en `compute` de nodes.nix.
        Agregalo ahí, o no importes este módulo desde hosts/${self}/default.nix.
      '';
    }
  ];

  boot.supportedFilesystems = [ "nfs" ];
  services.rpcbind.enable = true;

  # El directorio real, más el punto de montaje compartido. El setgid (2775)
  # hace que lo que se cree adentro quede en el grupo sisar-data, así el
  # directorio de job que arma un nodo es escribible desde otro.
  systemd.tmpfiles.rules = [
    "d /var/lib/sisar 0755 sisar sisar-data -"
    "d ${localRoot} 2775 sisar sisar-data -"
    "d ${sharedRoot} 0755 root root -"
  ];

  fileSystems =
    # El propio: bind mount, para que el dueño use el mismo nombre que los peers.
    {
      "${selfMount}" = {
        device = localRoot;
        fsType = "none";
        options = [
          "bind"
          # Sin x-systemd.automount: este montaje es local y el scheduler lo
          # necesita desde el arranque. Que falle acá es preferible a que el
          # scheduler escriba bajo un mountpoint vacío del disco de sistema.
          "x-systemd.requires-mounts-for=${localRoot}"
        ];
      };
    }
    # Los ajenos: NFS, uno por peer.
    // lib.mapAttrs' (
      peer: _:
      lib.nameValuePair "${sharedRoot}/${peer}/jobs" {
        device = "${peer}:/";
        fsType = "nfs4";
        options = mountOpts;
      }
    ) peers;

  systemd.services.nfs-server = {
    after = [ "systemd-tmpfiles-setup.service" ];
    unitConfig.RequiresMountsFor = localRoot;
  };

  services.nfs.server = {
    enable = true;
    # Puertos distintos a los 4000-4002 de sisar-server: no colisionan entre sí
    # (son hosts distintos), pero así se distingue a simple vista cuál NFS es
    # cuál en el firewall y en los logs.
    lockdPort = 4011;
    mountdPort = 4012;
    statdPort = 4010;

    exports = ''
      ${localRoot}  ${lanCidr}(${exportOpts},fsid=0)
    '';
  };

  # Debe coincidir con el dominio del servidor y de nfs-client.nix, o los
  # usuarios aparecen como nobody y las escrituras fallan.
  services.nfs.idmapd.settings = {
    General.Domain = "sisar.lan";
  };

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
