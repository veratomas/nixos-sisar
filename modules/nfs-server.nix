# Servidor NFS (host: sisar-nfs)
#
# NFSv4 con raíz en /srv/sisar (fsid=0). /srv/sisar es el disco de datos
# entero (ver disco-sisar.nix), no un directorio del disco de sistema: por eso
# alcanza con UN export y los clientes montan "sisar-nfs:/" sobre /srv/sisar,
# quedando el mismo path a los dos lados.
#
# Ya no hace falta `crossmnt`: no hay submontajes que cruzar, es un solo
# filesystem. Tampoco exports por subdirectorio — archive, jobs y logs son
# directorios comunes dentro del mismo árbol exportado.
{
  config,
  pkgs,
  lib,
  ...
}:
let
  # Red local autorizada a montar. Ajustar si tu LAN es otra.
  lanCidr = "192.168.0.0/24";

  # Opciones de exportación.
  #
  # `async` en vez de `sync`: con sync el servidor confirma cada escritura
  # recién cuando tocó el plato, y con cuatro nodos escribiendo SLC e
  # interferogramas eso cuesta caro. Con async confirma antes y el
  # rendimiento sube mucho.
  #
  # El riesgo: si sisar-nfs se apaga de golpe (corte de luz, panic), se
  # pierden escrituras que el cliente ya dio por buenas, y el cliente NO se
  # entera. Aceptable para archive/jobs/logs, que son reprocesables. Si el
  # servidor no tiene UPS, cambiá `async` por `sync`.
  opts = "rw,async,no_subtree_check,root_squash";
in
{
  # Estructura base del árbol. El resto (archive/dem/glo-30, archive/slc/
  # sentinel-1, archive/orbits/sentinel-1, archive/tropo/era5) se puede
  # agregar acá con la misma forma, o crearlo a mano; jobs/<uuid> y
  # logs/<uuid> los crea el pipeline.
  #
  # El setgid (2775) hace que todo lo que se cree adentro quede en el grupo
  # sisar-data, así el directorio de job que crea un nodo es escribible desde
  # otro. systemd-tmpfiles-setup corre después de local-fs.target, así que
  # estas reglas se aplican sobre el disco ya montado y no sobre el punto de
  # montaje vacío.
  systemd.tmpfiles.rules = [
    "d /srv/sisar         2775 sisar sisar-data -"
    "d /srv/sisar/archive 2775 sisar sisar-data -"
    "d /srv/sisar/jobs    2775 sisar sisar-data -"
    "d /srv/sisar/logs    2775 sisar sisar-data -"
  ];

  systemd.services.nfs-server = {
    after = [ "systemd-tmpfiles-setup.service" ];

    # /srv/sisar es un disco aparte. Sin esto, nfs-server podría arrancar
    # antes del montaje y exportar el directorio vacío que está debajo.
    unitConfig.RequiresMountsFor = "/srv/sisar";
  };

  services.nfs.server = {
    enable = true;
    # Puertos fijos, para poder abrirlos en el firewall de forma determinista.
    lockdPort = 4001;
    mountdPort = 4002;
    statdPort = 4000;

    # Un solo export: la raíz del disco. fsid=0 fija el file handle de la
    # raíz — sin él lo deriva del UUID del filesystem, y un reformateo o
    # clonado del disco deja a los clientes con "Stale file handle".
    exports = ''
      /srv/sisar  ${lanCidr}(${opts},fsid=0)
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
