# Cliente NFS (hosts: sisar1..sisar4)
#
# UN solo montaje: la raíz del export de sisar-nfs sobre /srv/sisar, el MISMO
# path que tiene el disco en el servidor. Adentro quedan archive/, jobs/ y
# logs/ como directorios comunes.
#
# Que el path coincida con el del servidor es lo que permite que un job
# armado en una máquina corra en otra: los job_spec.toml y los bind-mounts de
# Docker guardan rutas absolutas.
#
# Automount de systemd: el montaje se hace al primer acceso y el arranque no
# queda bloqueado si el servidor todavía no está disponible.
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

    # `hard` y no `soft`: acá los nodos ESCRIBEN resultados pesados. Con
    # `soft`, un timeout del servidor hace fallar la escritura, y muchas
    # herramientas no chequean el error de close(): el resultado son archivos
    # truncados que parecen completos, y un interferograma corrupto no se
    # nota hasta mucho después. Con `hard` el proceso espera a que el
    # servidor vuelva. `intr` no hace falta: en kernels modernos las señales
    # fatales interrumpen igual, así que Ctrl-C o kill siguen funcionando.
    "hard"
    "timeo=600"
    "retrans=2"

    # Archivos grandes: conviene el bloque máximo.
    "rsize=1048576"
    "wsize=1048576"

    "noatime"

    # Sin idle-timeout: desmontar el share por 10 minutos de inactividad
    # aparente, con jobs largos corriendo, es justo lo que no se quiere.
    "x-systemd.automount"
    "noauto"
  ];
in
{
  boot.supportedFilesystems = [ "nfs" ];
  services.rpcbind.enable = true;

  # ":/" es la raíz del export (fsid=0), que en el servidor es /srv/sisar.
  fileSystems."/srv/sisar" = {
    device = "${server}:/";
    fsType = "nfs4";
    options = mountOpts;
  };

  # Debe coincidir con el dominio del servidor o los usuarios aparecen como nobody.
  services.nfs.idmapd.settings = {
    General.Domain = "sisar.lan";
  };

  environment.systemPackages = with pkgs; [ nfs-utils ];
}
