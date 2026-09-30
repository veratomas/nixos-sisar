# Disco extra de sisar-server: ES /srv/sisar, la raíz del export NFS.
#
# El disco se monta directamente sobre /srv/sisar en vez de sobre un
# subdirectorio. Así archive/jobs/logs cuelgan de la raíz del export sin capa
# intermedia, el path queda idéntico en los cinco hosts, y los clientes tienen
# un solo montaje en lugar de uno por directorio.
#
#   sisar-server:  /srv/sisar  = este disco (local)
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
# ── Migración al disco de 7,3T (pendiente de ejecutar) ─────────────────────
#
# El WD10EZEX de 931G que está montado hoy queda corto: el archive (DEM, SLC,
# orbits, ERA5) crece sin techo y ya va por 375G. El reemplazo es un
# WD8006FFBX de 7,3T, hoy `sdc`, sin particionar. El disco viejo NO se borra:
# queda en la máquina como respaldo hasta que el nuevo esté probado.
#
# Etiqueta `sisar-data` y no `sisar`: el disco viejo ya es `sisar` y va a
# seguir enchufado. Dos discos con la misma etiqueta es exactamente cómo se
# monta el equivocado.
#
#   # 1. Preparar el disco nuevo. VERIFICAR la letra con lsblk antes de cada
#   #    comando: sda es el disco de datos viejo y sdb tiene /boot y /.
#   lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS
#   nix shell nixpkgs#parted nixpkgs#xfsprogs --command bash -ec '
#     D=/dev/sdc
#     wipefs -a $D
#     parted -s $D -- mklabel gpt
#     parted -s $D -- mkpart primary 0% 100%
#     partprobe $D; udevadm settle
#     mkfs.xfs -f -L sisar-data ${D}1
#   '
#   udevadm settle    # sin esto /dev/disk/by-label/ todavía no tiene el link
#
#   # 2. Bajar lo que escribe en /srv/sisar ANTES de copiar. Si el árbol se
#   #    mueve abajo de un rsync, la copia queda inconsistente en silencio.
#   sudo systemctl stop nfs-server sisar-server
#
#   # 3. Copiar. -aHAX preserva dueños, hardlinks, ACLs y atributos de XFS;
#   #    sin eso los 2775/sisar-data del árbol se pierden y los nodos dejan
#   #    de poder escribir. Tarda: son 375G.
#   sudo mkdir -p /mnt/sisar-nuevo
#   sudo mount /dev/disk/by-label/sisar-data /mnt/sisar-nuevo
#   sudo rsync -aHAX --info=progress2 /srv/sisar/ /mnt/sisar-nuevo/
#
#   # 4. Verificar ANTES de cortar. El segundo rsync debe no transferir nada.
#   sudo rsync -aHAXn --itemize-changes /srv/sisar/ /mnt/sisar-nuevo/ | head
#   sudo du -sh /srv/sisar /mnt/sisar-nuevo      # deben coincidir
#   sudo umount /mnt/sisar-nuevo
#
#   # 5. Recién ahora, cambiar el `device` de abajo a by-label/sisar-data
#   #    (la línea está lista, comentada) y reconstruir:
#   sudo nixos-rebuild switch --flake .#sisar-server
#   findmnt /srv/sisar                            # debe decir /dev/sdc1, 7,3T
#   systemctl status nfs-server
#
#   # 6. Con NFS arriba, remontar en los nodos y confirmar que ven el árbol:
#   #    (desde sisar-server)
#   for h in sisar1 sisar2 sisar3 sisar4 { ssh root@$h 'ls /srv/sisar' }
#
# El disco viejo queda sin montar y con sus datos intactos. Volver atrás es
# revertir el `device` a by-uuid/4b601fc0… y reconstruir.
#
# ── Si un nodo arranca durante la ventana, su scheduler queda muerto ───────
#
# Pasó en la migración del 2026-09-30 y conviene saberlo antes de la próxima.
# nfs-client.nix monta /srv/sisar con x-systemd.automount justamente para que
# el arranque no se bloquee si el servidor no está — pero sisar-scheduler
# declara RequiresMountsFor=/srv/sisar. Si el nodo arranca con el NFS caído,
# el montaje falla, el scheduler sale con "Dependency failed", y systemd NO
# reintenta: no es un Restart=, es una dependencia que ya se dio por perdida.
# El nodo queda arriba y sano, con el scheduler apagado hasta que alguien lo
# arranque a mano.
#
# Por eso el paso 6 no es opcional: después de levantar nfs-server hay que
# recorrer los nodos y confirmar que el scheduler está corriendo, no sólo que
# el share se ve.
#
#   for h in sisar1 sisar2 sisar3 sisar4 {
#     ssh root@$h 'systemctl is-active sisar-scheduler || systemctl start sisar-scheduler'
#   }
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
    # WD8006FFBX de 7,3T. La migración corrió el 2026-09-30: 18.940 archivos,
    # 383,5 GB, verificado con rsync en seco (sin diferencias) y comparando
    # tamaño aparente y cantidad de archivos y directorios.
    device = "/dev/disk/by-label/sisar-data";
    #
    # Disco viejo (WD10EZEX, 931G), todavía enchufado y con los datos intactos
    # bajo la etiqueta `sisar`. Es el rollback: volver a esta línea y
    # reconstruir. Borrarlo recién cuando el disco nuevo tenga varias semanas
    # de uso.
    # device = "/dev/disk/by-uuid/4b601fc0-4e23-4fa8-9ea5-17e4fa346613";
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
