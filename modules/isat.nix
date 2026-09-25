# modules/isat.nix
#
# Servidor ISAT: la API que usa el sitio web de /var/www/sisar.
#
# El frontend (HTML/JS) es estático y lo sirve nginx, pero cada pantalla habla
# con este backend por rutas relativas `/api/...`: login, listado de
# interferogramas, tiles, panel de admin. Sin este servicio nginx devuelve 404
# en /api/login y la pantalla de ingreso dice "no se pudo conectar al
# servidor" — que es exactamente lo que pasaba.
#
# OJO con el nombre: esto NO es `sisar-server` (modules/sisar-master.nix), que
# es la API de procesamiento en Rust y ya ocupa el 8080. Son dos servicios
# distintos; por eso ISAT va al 8081.
{
  lib,
  pkgs,
  inputs,
  ...
}:
let
  # Se compila desde el input `isat-src` (ver flake.nix): el código vive en
  # /var/www/sisar/isat-server.
  isat-server = pkgs.rustPlatform.buildRustPackage {
    pname = "isat-server";
    version = "0.1.0";
    src = inputs.isat-src;
    cargoLock.lockFile = inputs.isat-src + "/Cargo.lock";
    meta.description = "Servidor ISAT: API de usuarios, interferogramas y tiles";
  };

  # Sólo escucha en loopback: la puerta de entrada es nginx en el 80. Así no
  # hace falta abrir el 8081 en el firewall.
  puerto = 8081;

  # El frontend se sirve desde el directorio mutable a propósito, no desde el
  # nix store: mientras la página se está armando, editar un .js y recargar
  # tiene que alcanzar, sin rebuild. El binario sí sale del store.
  frontendDir = "/var/www/sisar/frontend";
in
{
  systemd.services.isat = {
    description = "Servidor ISAT (API del sitio web)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];

    environment = {
      ISAT_BIND = "127.0.0.1:${toString puerto}";
      ISAT_DB = "/var/lib/isat/isat.db";
      ISAT_FRONTEND_DIR = frontendDir;
      ISAT_UPLOADS_DIR = "/var/lib/isat/interferogramas";
      # Los procesamientos del pipeline SISAR, que el panel de admin importa
      # desde /api/admin/jobs. NO es un directorio propio de ISAT: lo escribe
      # el pipeline en el disco de datos, y el vigilante lo revisa cada 300s.
      ISAT_JOBS_DIR = "/srv/sisar/jobs";
      ISAT_MAX_UPLOAD_MB = "500";
    };

    serviceConfig = {
      ExecStart = lib.getExe' isat-server "isat-server";

      # Sin ISAT_ADMIN_PASSWORD el servidor genera una clave aleatoria en el
      # primer arranque y la escribe en el journal:
      #   journalctl -u isat | grep -i admin
      # Es a propósito: una clave fija acá quedaría en el nix store, que es
      # legible por cualquier usuario de la máquina.

      DynamicUser = true;
      StateDirectory = "isat";
      Restart = "on-failure";
      RestartSec = 5;

      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      CapabilityBoundingSet = "";
    };
  };
}
