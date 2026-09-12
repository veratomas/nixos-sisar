# El API server de SISAR, como servicio de systemd. Corre sólo en sisar-server.
#
# Desde esta sesión el servidor NO toca el sistema de archivos para crear jobs:
# registra el pedido en la base y un scheduler con capacidad arma el directorio
# en su propio disco. Por eso acá no hay `jobs_root` — el servidor no tiene, ni
# necesita, acceso al almacenamiento de los nodos.
#
# Lo que sí lee es el árbol central: los demos y (desde la fase 4) los
# resultados exportados.
#
# El paquete no tiene default, por la misma razón que en sisar-scheduler.nix:
# vive en el repo sisar-server, que se publica aparte.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.sisar.server;

  toml = pkgs.formats.toml { };

  serverConfig = toml.generate "config.toml" (
    {
      server = {
        listen = cfg.listen;
      };

      database = {
        url = cfg.databaseUrl;
        pool_size = cfg.databasePoolSize;
      };

      paths = {
        archive_root = "${cfg.centralRoot}/archive";
        demos_root = "${cfg.centralRoot}/demos";
        # De acá salen los resultados que sirve la API. No hay jobs_root: el
        # servidor no crea directorios ni lee el disco de ningún nodo.
        results_root = "${cfg.centralRoot}/results";
      };

      asf = {
        endpoint = cfg.asfEndpoint;
      };

      defaults = cfg.processingDefaults;
      user_tiers = cfg.userTiers;
    }
    // lib.optionalAttrs (cfg.interfaceTokensFile == null) {
      auth.interface_tokens = cfg.interfaceTokens;
    }
  );
in
{
  options.services.sisar.server = {
    enable = lib.mkEnableOption "el API server de SISAR";

    package = lib.mkOption {
      type = lib.types.package;
      description = "El paquete que trae el binario `sisar-server`. Ver el comentario del módulo.";
    };

    listen = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0:8080";
    };

    centralRoot = lib.mkOption {
      type = lib.types.str;
      default = "/srv/sisar";
      description = "Raíz del árbol central. Es un disco local en este host (disco-sisar.nix).";
    };

    databaseUrl = lib.mkOption {
      type = lib.types.str;
      default = "postgres:///sisar?host=/run/postgresql&user=sisar";
      description = ''
        PostgreSQL corre en este mismo host, así que por defecto se conecta por
        socket unix: sin contraseña que guardar y sin puerto expuesto.
      '';
    };

    databasePoolSize = lib.mkOption {
      type = lib.types.int;
      default = 10;
    };

    asfEndpoint = lib.mkOption {
      type = lib.types.str;
      default = "https://api.daac.asf.alaska.edu/services/search/param";
    };

    interfaceTokens = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        telegram = "un-token";
      };
      description = ''
        Un bearer token por interfaz, que identifica a la INTERFAZ y no al
        usuario. Definirlos acá los deja en el store, que es legible por todo
        el sistema: sirve para probar, no para producción. Para producción usar
        `interfaceTokensFile`.
      '';
    };

    interfaceTokensFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Ruta fuera del store a un TOML con la sección `[auth.interface_tokens]`,
        concatenada al config generado al arrancar. Es la forma de tener tokens
        que no queden legibles en el store. Debe ser legible por el usuario
        `sisar` y por nadie más.
      '';
    };

    processingDefaults = lib.mkOption {
      type = toml.type;
      default = {
        range_looks = 40;
        azimuth_looks = 10;
        connections = 1;
        max_acquisitions = 30;
      };
      description = "Lo que se aplica a un pedido que no lo especifica.";
    };

    userTiers = lib.mkOption {
      type = toml.type;
      default = {
        demo = {
          max_aoi_km2 = 500;
          max_time_range_days = 30;
          max_concurrent_jobs = 1;
          max_jobs_per_month = 3;
        };
        free = {
          max_aoi_km2 = 2000;
          max_time_range_days = 180;
          max_concurrent_jobs = 2;
          max_jobs_per_month = 10;
        };
        pro = {
          max_aoi_km2 = 0;
          max_time_range_days = 0;
          max_concurrent_jobs = 5;
          max_jobs_per_month = 0;
        };
      };
      description = ''
        Límites por tier, validados en el momento de aceptar el job. Tienen que
        coincidir con los del scheduler, que usa `max_concurrent_jobs` al
        despachar.
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Abre el puerto de `listen` en el firewall.";
    };

    logLevel = lib.mkOption {
      type = lib.types.str;
      default = "info";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.sisar-server = {
      description = "SISAR API server";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network-online.target"
        "postgresql.service"
      ];
      wants = [ "network-online.target" ];

      # Lee demos y resultados del árbol central; arrancar antes del montaje
      # daría 404 en vez de un error claro.
      unitConfig.RequiresMountsFor = [ cfg.centralRoot ];

      environment = {
        RUST_LOG = cfg.logLevel;
      };

      serviceConfig =
        {
          User = "sisar";
          Group = "sisar";
          SupplementaryGroups = [ "sisar-data" ];
          Restart = "always";
          RestartSec = 10;

          # El servidor ya no escribe en disco: registra el pedido en la base y
          # sirve archivos del árbol central. Lo único que necesita escribir es
          # nada, así que se le puede apretar bastante.
          NoNewPrivileges = true;
          PrivateDevices = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectControlGroups = true;
          RestrictSUIDSGID = true;
          ProtectHome = true;
        }
        // (
          if cfg.interfaceTokensFile == null then
            {
              ExecStart = "${cfg.package}/bin/sisar-server";
              Environment = [ "SERVER_CONFIG=${serverConfig}" ];
            }
          else
            {
              # Los tokens se concatenan al config generado en un directorio
              # de runtime, para que nunca pasen por el store.
              RuntimeDirectory = "sisar-server";
              RuntimeDirectoryMode = "0700";
              ExecStartPre = pkgs.writeShellScript "sisar-server-config" ''
                umask 077
                cat ${serverConfig} ${cfg.interfaceTokensFile} \
                  > "$RUNTIME_DIRECTORY/config.toml"
              '';
              ExecStart = "${cfg.package}/bin/sisar-server";
              Environment = [ "SERVER_CONFIG=%t/sisar-server/config.toml" ];
            }
        );
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [
      (lib.toInt (lib.last (lib.splitString ":" cfg.listen)))
    ];
  };
}
