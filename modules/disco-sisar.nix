# Disco extra de sisar-nfs: ES /srv/sisar, la raíz del export NFS.
#
# El disco se monta directamente sobre /srv/sisar en vez de sobre un
# subdirectorio. Así archive/jobs/logs cuelgan de la raíz del export sin capa
# intermedia, el path queda idéntico en los cinco hosts, y los clientes tienen
# un solo montaje en lugar de uno por directorio.
#
#   sisar-nfs:  /srv/sisar  = este disco (local)
#   sisar1..4:  /srv/sisar  = el mismo árbol, por NFS
#
# Que el path coincida no es estético: los job_spec.toml, los bind-mounts de
# Docker y los logs guardan rutas absolutas. Si difiriera entre nodos, un job
# armado en una máquina apuntaría a un path inexistente en otra.
#
# ── Preparación, UNA sola vez y a mano (Nix no formatea nada) ──────────────
#
#   # parted va SIEMPRE al disco (sdb); mkfs va SIEMPRE a la partición (sdb1).
#   lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS   # identificar el disco
#   sudo wipefs -a /dev/sdb                       # borrar firmas viejas
#   sudo parted /dev/sdb -- mklabel gpt
#   sudo parted /dev/sdb -- mkpart primary 0% 100%
#   sudo partprobe /dev/sdb
#   sudo mkfs.xfs -f -L sisar /dev/sdb1
#   sudo blkid /dev/sdb1                          # <- el UUID va acá abajo
#
# Si mkfs se queja de "contains a mounted filesystem", el gestor de archivos
# montó la partición solo: cerralo y `udisksctl unmount -b /dev/sdb1`.
#
# XFS y no ext4: archivos grandes (SLC, DEM, interferogramas). XFS rinde
# mejor en ese perfil y no reserva el 5% del volumen para root.
#
{
  config,
  pkgs,
  lib,
  ...
}:
{
  # Sin esto, mkfs.xfs y xfs_repair no quedan en el PATH del sistema y el
  # soporte de XFS depende de la autodetección.
  boot.supportedFilesystems = [ "xfs" ];

  fileSystems."/srv/sisar" = {
    device = "/dev/disk/by-uuid/4b601fc0-4e23-4fa8-9ea5-17e4fa346613";
    fsType = "xfs";
    options = [
      "defaults"
      "noatime"
      # nofail: si el disco no aparece, el servidor igual arranca y se puede
      # entrar por SSH a diagnosticar. nfs-server NO levanta sin él (ver
      # RequiresMountsFor en nfs-server.nix), y es deliberado: exportar el
      # directorio vacío de abajo sería peor — los clientes verían un árbol
      # vacío sin ningún error y los jobs escribirían contra el disco de
      # sistema hasta llenarlo.
      "nofail"
      "x-systemd.device-timeout=10s"
    ];
  };

  # Herramientas de XFS (xfs_repair, xfs_growfs, xfs_quota).
  environment.systemPackages = with pkgs; [ xfsprogs ];
}
