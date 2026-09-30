# Disco de datos de un nodo de cómputo: ES /var/lib/sisar/jobs.
#
# Es el disco que storage-nodes.nix venía anticipando. Ahí está escrito el
# contrato: `localRoot` (/var/lib/sisar/jobs) era un directorio del disco de
# sistema porque los nodos no tenían disco propio, y "cuando lo tengan, alcanza
# con un fileSystems que monte ese disco en `localRoot`". Esto es ese
# fileSystems. storage-nodes.nix no cambia.
#
# La cadena queda así, y conviene tenerla entera a la vista:
#
#   /dev/disk/by-label/sisar-jobs            este disco
#     -> /var/lib/sisar/jobs                 localRoot, lo que exporta el nodo
#       -> /srv/sisar-nodes/<nodo>/jobs      bind mount, el nombre compartido
#
# El bind mount y el porqué del nombre compartido están explicados en
# storage-nodes.nix; no los repito acá.
#
# ── Por qué by-label y no by-uuid ───────────────────────────────────────────
#
# disco-sisar.nix usa by-uuid porque es UN disco en UN host. Acá son tres
# discos idénticos (WD8006FFBX) en tres hosts, con el mismo rol y el mismo
# punto de montaje: con UUID harían falta tres módulos, o un atributo por host
# en cada hosts/sisarN/default.nix. La etiqueta es lo que permite que los tres
# nodos importen el MISMO archivo.
#
# El costo de la etiqueta es que no es única por construcción: un disco ajeno
# etiquetado `sisar-jobs` que se enchufe en un nodo se montaría como si fuera
# el propio. Es un riesgo real pero acotado — son máquinas fijas en un rack —
# y a cambio evita tres copias de este módulo divergiendo con el tiempo.
# `sisar-jobs` y no `sisar` a propósito: `sisar` ya es la etiqueta del disco de
# sisar-server (disco-sisar.nix), y que un disco de datos del servidor
# terminara montado sobre el jobs/ de un nodo sería mucho peor que no montar
# nada.
#
# ── Preparación, UNA sola vez y a mano (Nix no formatea nada) ──────────────
#
# Un nodo pelado NO tiene parted ni mkfs.xfs: xfsprogs entra recién con este
# módulo, y para entonces ya hace falta el filesystem. De ahí el `nix shell`.
#
#   lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS   # identificar el disco
#
#   nix shell nixpkgs#parted nixpkgs#xfsprogs --command bash -ec '
#     D=/dev/sdX                                  # <- VERIFICAR, ver abajo
#     wipefs -a $D
#     parted -s $D -- mklabel gpt
#     parted -s $D -- mkpart primary 0% 100%
#     partprobe $D
#     udevadm settle
#     mkfs.xfs -f -L sisar-jobs ${D}1
#   '
#   udevadm settle
#   blkid ${D}1                                   # confirmar LABEL y TYPE
#
# El `udevadm settle` después de mkfs no es decorativo: sin él,
# /dev/disk/by-label/sisar-jobs todavía no existe y el primer `mount` falla
# con "Can't lookup blockdev".
#
# OJO con la letra del disco. NO es estable: depende de qué discos haya y en
# qué orden los enumere el kernel. En estos nodos el disco de datos apareció
# primero como `sda` y después de un reboot como `sdb`. Mirar lsblk ANTES de
# cada comando y confirmar por modelo y tamaño, no por letra — el disco de
# sistema tiene /boot y /, y un parted contra el equivocado se lleva puesto
# el nodo. Que el montaje de abajo vaya por etiqueta y no por letra es
# justamente lo que hace que ese baile de letras no rompa nada.
#
# XFS por lo mismo que en disco-sisar.nix: archivos grandes (SLC, DEM,
# interferogramas), y no reserva el 5% del volumen para root.
{
  config,
  pkgs,
  lib,
  ...
}:
{
  boot.supportedFilesystems = [ "xfs" ];

  fileSystems."/var/lib/sisar/jobs" = {
    device = "/dev/disk/by-label/sisar-jobs";
    fsType = "xfs";
    options = [
      "defaults"
      "noatime"

      # nofail: si el disco no aparece, el nodo igual arranca y se puede entrar
      # por SSH a diagnosticar, en vez de quedarse en emergency mode sin red.
      #
      # No deja al scheduler escribiendo sobre el directorio vacío de abajo, que
      # es lo que habría que temer: el bind mount de storage-nodes.nix lleva
      # `x-systemd.requires-mounts-for` sobre este path, y la unidad
      # sisar-scheduler declara RequiresMountsFor sobre
      # /srv/sisar-nodes/<nodo>/jobs. Si este montaje falla, la cadena corta
      # sola y el scheduler no arranca. Un nodo que no toma trabajo se nota;
      # uno que llena su disco de sistema, no.
      "nofail"
      "x-systemd.device-timeout=10s"
    ];
  };

  environment.systemPackages = with pkgs; [ xfsprogs ];
}
