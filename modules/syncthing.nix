# Syncthing en sisar-server, con la carpeta sincronizada sobre el disco de 8 TB.
#
# ── Por qué el bind-mount y no un path directo ─────────────────────────────
#
# El disco de 8 TB (WD8006FFBX, label `sisar-data`) está ENTERO montado sobre
# /srv/sisar: una sola partición, un solo filesystem, sin espacio libre fuera
# de ese montaje (ver disco-sisar.nix). No hay forma de poner datos en ese
# disco "al lado" de /srv/sisar sin reparticionar, y XFS no se puede encoger.
#
# Para que la carpeta de Syncthing NO quede montada bajo /srv/sisar, los datos
# viven en un subdirectorio del disco y se exponen por bind-mount en un path
# propio, fuera del árbol de SISAR:
#
#   /srv/sisar/syncthing        <- dónde están los bytes (el disco de 8 TB)
#   /var/lib/syncthing/data     <- el path que ve Syncthing (bind del anterior)
#
# Syncthing sólo conoce /var/lib/syncthing/data. Nada en su configuración
# apunta a /srv/sisar, así que el día que la carpeta se mueva a otro disco
# alcanza con cambiar el `what` del montaje de abajo.
#
# OJO — el bind-mount cambia el path, no el filesystem: /srv/sisar/syncthing
# sigue estando dentro del único export NFS (/srv/sisar, ver nfs-server.nix),
# así que sisar1..4 ven y pueden escribir esos archivos por NFS. Si eso no se
# quiere, la única solución real es una partición aparte en otro disco: no se
# puede esconder un subdirectorio de un export con no_subtree_check.
#
# ── Dueño y grupo ──────────────────────────────────────────────────────────
#
# sisar:sisar-data, igual que el resto del árbol del disco, con setgid 2775:
# así los admins (todos en sisar-data) pueden tocar la carpeta sin sudo y lo
# que Syncthing cree no queda con un grupo distinto al del resto del disco.
#
# ── Acceso a la GUI: por Tailscale ─────────────────────────────────────────
#
# La GUI escucha en 0.0.0.0:8384, pero el puerto NO está en
# networking.firewall.allowedTCPPorts: en la LAN y en internet queda cerrado.
# Lo único que entra es tailscale0, que tailscale.nix declara interfaz
# confiable (trustedInterfaces), más localhost. O sea:
#
#   http://sisar-server:8384/      <- desde cualquier máquina del tailnet
#   http://100.84.232.33:8384/     <- la misma, por IP, si no resuelve el nombre
#
# Se bindea a 0.0.0.0 y no a la IP de Tailscale a propósito: con la IP, si
# syncthing arranca antes de que tailscaled levante la interfaz, el bind falla
# y el servicio queda caído. El firewall da la misma restricción sin la
# carrera.
#
# ── CONTRASEÑA: hay que crear el archivo (si no, la GUI queda abierta) ─────
#
# El tailnet NO es sólo nuestro: hay máquinas de gente que no administra el
# cluster, y cualquiera de ellas llega al 8384. Con la GUI sin contraseña eso
# es control total de Syncthing. Por eso guiPasswordFile, en la misma línea
# que interfaceTokensFile del servidor: la contraseña no va al store (sería
# legible por cualquier usuario del sistema), va a un archivo aparte.
#
# UNA sola vez, antes del primer `nixos-rebuild switch`:
#
#   sudo install -d -m 0755 /etc/sisar
#   openssl rand -base64 24 | sudo tee /etc/sisar/syncthing-gui-password
#   sudo chown sisar:root /etc/sisar/syncthing-gui-password
#   sudo chmod 0400 /etc/sisar/syncthing-gui-password
#
# Tiene que poder leerlo el usuario `sisar`: lo lee syncthing-init.service,
# que corre como ese usuario y hashea el contenido con bcrypt antes de
# mandárselo a Syncthing por su API. Cambiar la contraseña es editar el
# archivo y `systemctl restart syncthing-init`.
#
# Si el archivo no existe, syncthing-init falla y la GUI queda SIN
# contraseña, escuchando en el tailnet. Verificar después del switch:
#
#   systemctl status syncthing-init     # debe decir exited/success
#
# ── Emparejar peers (se puede entero por SSH, sin GUI) ─────────────────────
#
# Los peers NO se declaran acá (overrideDevices/overrideFolders = false): se
# agregan desde la GUI y Nix no los borra en el próximo rebuild. Lo mismo por
# línea de comandos, con `syncthing cli`:
#
#   export STHOMEDIR=/var/lib/syncthing/config
#   sudo -u sisar -E syncthing cli show system | grep myID      # nuestro ID
#   sudo -u sisar -E syncthing cli config devices add --device-id <ID-DEL-OTRO>
#   sudo -u sisar -E syncthing cli config folders sisar-sync devices add \
#       --device-id <ID-DEL-OTRO>
#
{
  config,
  pkgs,
  lib,
  ...
}:
let
  # Subdirectorio del disco de 8 TB donde quedan los bytes.
  backingDir = "/srv/sisar/syncthing";

  # Path por el que Syncthing accede a la carpeta. Fuera de /srv/sisar.
  dataDir = "/var/lib/syncthing/data";

  configDir = "/var/lib/syncthing/config";
in
{
  # El subdirectorio del disco y el punto de montaje. systemd-tmpfiles-setup
  # corre después de local-fs.target, o sea con /srv/sisar ya montado: la
  # primera regla cae sobre el disco y no sobre el directorio vacío de abajo.
  systemd.tmpfiles.rules = [
    "d ${backingDir} 2775 sisar sisar-data -"
    "d /var/lib/syncthing 0755 sisar sisar-data -"
    "d ${dataDir} 0755 sisar sisar-data -"
    "d ${configDir} 0700 sisar sisar-data -"
  ];

  # El bind-mount va como systemd.mounts y no como fileSystems: el origen lo
  # crea tmpfiles, que corre DESPUÉS de local-fs.target. Un fileSystems acá
  # entraría en local-fs.target y fallaría en el primer arranque (el origen
  # todavía no existe) o armaría un ciclo de dependencias con tmpfiles.
  systemd.mounts = [
    {
      what = backingDir;
      where = dataDir;
      type = "none";
      options = "bind";

      requires = [ "systemd-tmpfiles-setup.service" ];
      after = [ "systemd-tmpfiles-setup.service" ];
      unitConfig.RequiresMountsFor = "/srv/sisar";
      wantedBy = [ "multi-user.target" ];
    }
  ];

  services.syncthing = {
    enable = true;

    user = "sisar";
    group = "sisar-data";

    inherit dataDir configDir;

    # Puertos de sincronización y descubrimiento en la LAN: 22000 TCP/UDP y
    # 21027 UDP. La GUI (8384) NO se abre en el firewall: llega sólo por
    # tailscale0 (interfaz confiable) y por localhost. Ver el comentario de
    # arriba.
    openDefaultPorts = true;
    guiAddress = "0.0.0.0:8384";

    # Contraseña fuera del store. El usuario va declarado acá porque no es
    # secreto; el archivo lo crea el admin a mano (ver arriba).
    guiPasswordFile = "/etc/sisar/syncthing-gui-password";
    settings.gui.user = "sisar";

    # Nix declara la carpeta; los dispositivos se emparejan por GUI. Con los
    # override en false, Syncthing conserva lo agregado a mano en lugar de
    # perderlo en cada rebuild.
    overrideDevices = false;
    overrideFolders = false;

    settings.folders."sisar-sync" = {
      id = "sisar-sync";
      label = "sisar-sync";
      path = dataDir;
      type = "sendreceive";
      # Las versiones viejas van al disco de 8 TB, no al de sistema: quedan en
      # .stversions dentro de la propia carpeta.
      versioning = {
        type = "staggered";
        params.maxAge = toString (30 * 24 * 3600); # 30 días
      };
    };
  };

  # Sin esto, si el disco no monta Syncthing arranca igual y empieza a
  # sincronizar contra el directorio vacío del disco de sistema — y lo que ve
  # como "carpeta vacía" lo propaga a los peers como borrado.
  systemd.services.syncthing.unitConfig.RequiresMountsFor = dataDir;
}
