# Nextcloud en sisar-server, para sincronizar archivos del equipo (13 personas).
#
# Reemplaza a Syncthing. Sirve para: el vault de Obsidian (plugin "Nextcloud
# Sync", con merge de tres vías), PDFs, archivos de CAD (FreeCAD, AutoCAD) y
# alguna planilla de Excel. El código NO va acá: sigue en GitHub. Fusion
# tampoco: vive en la nube de Autodesk.
#
# ── Por qué un contenedor ──────────────────────────────────────────────────
#
# Nextcloud corre en un contenedor NixOS (systemd-nspawn) con su propio nginx,
# php-fpm, PostgreSQL y Redis. Lo único que comparte con SISAR es el nginx del
# host, que sólo le pasa el tráfico de un virtualHost propio. Así:
#
#   - no toca la configuración del PostgreSQL de SISAR (pg_hba con
#     mkOverride, max_connections, la espera de la IP de la LAN);
#   - un upgrade de Nextcloud o de su PostgreSQL no reinicia nada de SISAR;
#   - mudarlo a otro nodo es importar este módulo allá y copiar dos árboles:
#
#       /var/lib/nixos-containers/nextcloud   <- raíz del contenedor: base,
#                                                config.php, secretos (disco
#                                                de sistema)
#       /srv/sisar/nextcloud/data             <- los archivos (disco de 8 TB)
#
# ── Acceso: sólo por Tailscale, con HTTPS ──────────────────────────────────
#
# Todos los clientes usan Tailscale, también en la oficina (en la LAN el
# tráfico va directo por la LAN, sin pasar por un relay). Un solo nombre y un
# solo certificado, válido en todos lados:
#
#   https://sisar-server.tail7bbeb7.ts.net/
#
# El 443 NO se abre en el firewall: entra sólo por tailscale0, que
# tailscale.nix declara interfaz confiable. El certificado lo emite Tailscale
# (Let's Encrypt) con `tailscale cert`; ver tailscale-cert-nextcloud abajo.
#
# Requiere, UNA vez, habilitar "HTTPS Certificates" en la consola de admin de
# Tailscale (DNS → HTTPS Certificates). OJO: el nombre de la máquina queda en
# los logs públicos de Certificate Transparency.
#
# ── Los datos están DENTRO del export NFS (provisorio) ─────────────────────
#
# /srv/sisar/nextcloud cuelga del único export NFS (ver nfs-server.nix): no se
# puede esconder un subdirectorio de un export, así que sisar1..4 lo ven, y un
# bind-mount no cambia eso (cambia el path, no el filesystem). Se acepta para
# la prueba. Mitigación: dueño con UID/GID fijo (3500) que no existe en
# ningún nodo, y modo 0700. Nadie en los nodos tiene que escribir ahí: un
# cambio por fuera de Nextcloud no lo ve hasta un `occ files:scan`.
#
# Lo definitivo es un disco (o nodo) propio: cambiar `dataDir` y copiar.
#
# ── CONTRASEÑA DEL ADMIN: hay que crear el archivo antes del primer switch ─
#
# Sólo se usa en la instalación inicial (después la contraseña vive en la
# base y se cambia desde la web). Sin el archivo el contenedor no arranca.
#
#   sudo install -d -m 0755 /etc/sisar
#   openssl rand -base64 24 | sudo tee /etc/sisar/nextcloud-admin-pass
#   sudo chown 3500:3500 /etc/sisar/nextcloud-admin-pass
#   sudo chmod 0400 /etc/sisar/nextcloud-admin-pass
#
# ── Administración ─────────────────────────────────────────────────────────
#
#   sudo nixos-container root-login nextcloud
#   nextcloud-occ status
#   nextcloud-occ files:lock <fileId> --unlock     # liberar un lock olvidado
#
{
  config,
  pkgs,
  lib,
  ...
}:
let
  hostName = "sisar-server.tail7bbeb7.ts.net";

  # Red privada host <-> contenedor. Sólo existe entre estos dos extremos.
  hostAddress = "10.233.1.1";
  localAddress = "10.233.1.2";

  # UID/GID fijos del usuario nextcloud. Fijos porque el directorio de datos
  # se ve por NFS desde los nodos: un UID asignado dinámicamente podría
  # coincidir con el de un usuario real en algún nodo. 3500 no existe en
  # ninguno (los usuarios reales van de 1000 en adelante, de a uno).
  ncId = 3500;

  # Dónde quedan los archivos en el host.
  baseDir = "/srv/sisar/nextcloud";
  dataDir = "${baseDir}/data";

  adminPassFile = "/etc/sisar/nextcloud-admin-pass";

  certDir = "/var/lib/tailscale-cert";
  certFile = "${certDir}/${hostName}.crt";
  keyFile = "${certDir}/${hostName}.key";
in
{
  # ── Contenedor ────────────────────────────────────────────────────────────

  containers.nextcloud = {
    autoStart = true;
    privateNetwork = true;
    inherit hostAddress localAddress;

    bindMounts = {
      "/var/lib/nextcloud/data" = {
        hostPath = dataDir;
        isReadOnly = false;
      };
      "/run/secrets/nextcloud-admin-pass" = {
        hostPath = adminPassFile;
        isReadOnly = true;
      };
    };

    config =
      { config, pkgs, ... }:
      {
        users.users.nextcloud.uid = ncId;
        users.groups.nextcloud.gid = ncId;

        services.nextcloud = {
          enable = true;
          # Versión mayor explícita: NixOS no salta de mayor solo, y cada
          # salto hay que hacerlo de a uno (34 -> 35 -> ...).
          package = pkgs.nextcloud34;
          inherit hostName;
          https = true;

          maxUploadSize = "16G";
          configureRedis = true;
          database.createLocally = true;

          # Lo más liviano posible: sin tienda de apps. Lo que haga falta
          # entra por acá, empaquetado en nixpkgs.
          appstoreEnable = false;
          extraApps = {
            inherit (config.services.nextcloud.package.packages.apps) groupfolders;
          };
          extraAppsEnable = true;

          config = {
            dbtype = "pgsql";
            adminuser = "admin";
            adminpassFile = "/run/secrets/nextcloud-admin-pass";
          };

          settings = {
            # El nginx del host termina TLS y reenvía por la red privada.
            trusted_proxies = [ hostAddress ];
            default_phone_region = "AR";
            # Hora UTC: 06 = 03 en Argentina.
            maintenance_window_start = 6;
            # Sin salida a internet desde el contenedor: evita que Nextcloud
            # espere timeouts buscando actualizaciones o apps.
            has_internet_connection = false;
          };
        };

        # Lo que el módulo no declara: se aplica en cada arranque, es
        # idempotente.
        #
        #   files_lock: el lock manual desde el cliente de escritorio
        #     (clic derecho → Lock file). Viene con Nextcloud pero apagado.
        #   windows-compatible-filenames: rechaza en el servidor nombres que
        #     Windows no puede crear (: ? * " < > |, CON, NUL, …), para que
        #     un archivo creado en Linux no rompa la sincronización de los
        #     clientes Windows.
        systemd.services.nextcloud-sisar-setup = {
          description = "Ajustes de Nextcloud que el módulo no declara";
          after = [ "nextcloud-setup.service" ];
          requires = [ "nextcloud-setup.service" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig.Type = "oneshot";
          script = ''
            ${lib.getExe config.services.nextcloud.occ} app:enable files_lock
            ${lib.getExe config.services.nextcloud.occ} files:windows-compatible-filenames --enable
          '';
        };

        # Backup diario de la base, dentro del contenedor. Queda en el disco
        # de sistema (/var/lib/nixos-containers/nextcloud/var/backup/…), o sea
        # en un disco distinto del de los archivos. Los archivos en sí NO
        # tienen backup todavía.
        services.postgresqlBackup = {
          enable = true;
          databases = [ "nextcloud" ];
          startAt = "*-*-* 03:30:00";
        };

        networking.firewall.allowedTCPPorts = [ 80 ];

        system.stateVersion = "25.11";
      };
  };

  systemd.tmpfiles.rules = [
    "d ${certDir} 0750 root nginx -"
  ];

  systemd.services."container@nextcloud" = {
    # Sin el disco montado, el contenedor escribiría en el directorio vacío
    # del disco de sistema, y los clientes verían la nube vacía y borrarían
    # todo.
    unitConfig.RequiresMountsFor = "/srv/sisar";

    # El directorio de datos se crea acá y no con tmpfiles: /srv/sisar es de
    # `sisar`, y tmpfiles se niega a crear adentro algo de otro usuario no
    # root ("Detected unsafe path transition"), así que la regla no hacía
    # nada y el contenedor no arrancaba por falta del bind-mount.
    #
    # setfacl -b: /srv/sisar tiene una ACL por defecto que da rwx a
    # sisar-data y que todo directorio nuevo hereda. Sin borrarla, los
    # archivos de Nextcloud quedarían escribibles para ese grupo, también
    # desde los nodos por NFS.
    preStart = lib.mkBefore ''
      ${pkgs.coreutils}/bin/install -d -m 0711 -o root -g root ${baseDir}
      ${pkgs.coreutils}/bin/install -d -m 0750 -o ${toString ncId} -g ${toString ncId} ${dataDir}
      ${pkgs.acl}/bin/setfacl -b ${baseDir} ${dataDir}
    '';
  };

  # NetworkManager no tiene que tocar la interfaz veth del contenedor.
  networking.networkmanager.unmanaged = [ "interface-name:ve-*" ];

  # ── Certificado de Tailscale ──────────────────────────────────────────────
  #
  # El nginx del host sirve también el sitio de SISAR: si al arrancar le
  # falta un certificado, no levanta NINGÚN virtualHost. Por eso, si
  # `tailscale cert` falla (tailscaled caído, HTTPS no habilitado en la
  # consola), se genera uno autofirmado provisorio: Nextcloud queda con
  # advertencia de certificado, pero el sitio de SISAR no se cae.
  systemd.services.tailscale-cert-nextcloud = {
    description = "Certificado de Tailscale para Nextcloud";
    wants = [ "tailscaled.service" ];
    after = [ "tailscaled.service" ];
    before = [ "nginx.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [
      config.services.tailscale.package
      pkgs.coreutils
      pkgs.openssl
      pkgs.systemd
    ];
    serviceConfig.Type = "oneshot";
    script = ''
      if timeout 120 tailscale cert \
           --cert-file ${certFile}.new --key-file ${keyFile}.new ${hostName}; then
        mv ${certFile}.new ${certFile}
        mv ${keyFile}.new ${keyFile}
      elif [ ! -s ${certFile} ]; then
        echo "tailscale cert falló: certificado autofirmado provisorio" >&2
        openssl req -x509 -newkey rsa:2048 -nodes -days 7 -subj "/CN=${hostName}" \
          -keyout ${keyFile} -out ${certFile}
      fi
      chgrp nginx ${certFile} ${keyFile}
      chmod 0640 ${certFile} ${keyFile}
      # --no-block: nginx está ordenado DESPUÉS de este servicio, así que un
      # reload bloqueante espera a que este servicio termine, y este servicio
      # espera al reload. Se trabó así el primer switch.
      if systemctl is-active --quiet nginx; then systemctl reload --no-block nginx; fi
    '';
  };

  # Los certificados de Let's Encrypt duran 90 días; tailscale los renueva
  # cuando se acercan al vencimiento. Correrlo a diario alcanza.
  systemd.timers.tailscale-cert-nextcloud = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      RandomizedDelaySec = "1h";
      Persistent = true;
    };
  };

  systemd.services.nginx = {
    wants = [ "tailscale-cert-nextcloud.service" ];
    after = [ "tailscale-cert-nextcloud.service" ];
  };

  # ── Proxy en el nginx del host ────────────────────────────────────────────
  #
  # onlySSL: escucha sólo en el 443, que no está abierto en el firewall. El
  # virtualHost de SISAR (nginx.nix) sigue siendo el default del 80.
  services.nginx.virtualHosts.${hostName} = {
    onlySSL = true;
    sslCertificate = certFile;
    sslCertificateKey = keyFile;

    locations."/" = {
      proxyPass = "http://${localAddress}";
      proxyWebsockets = true;
      recommendedProxySettings = true;
      # Subidas grandes (CAD) sin límite de tamaño en el proxy ni copia
      # intermedia en disco: el límite real lo pone Nextcloud (maxUploadSize).
      extraConfig = ''
        client_max_body_size 0;
        proxy_request_buffering off;
        proxy_buffering off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
      '';
    };
  };
}
