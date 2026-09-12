# El scheduler de SISAR, como servicio de systemd.
#
# Un proceso por nodo de cómputo. Reclama tareas de la cola en PostgreSQL,
# corre contenedores de Docker contra el directorio de trabajo del job, y desde
# esta sesión también reclama el ALMACENAMIENTO de los jobs nuevos: crea el
# directorio en el disco de este nodo y escribe job_spec.toml.
#
# El paquete no tiene default a propósito: vive en el repo sisar-server, que se
# publica aparte (github:veratomas/sisar-server). Para conectarlo, agregar el
# input al flake y pasar el paquete acá:
#
#   # flake.nix
#   inputs.sisar.url = "github:veratomas/sisar-server";
#   # hosts/<nodo>/default.nix
#   services.sisar.scheduler = {
#     enable  = true;
#     package = inputs.sisar.packages.x86_64-linux.scheduler;
#   };
#
# Se deja sin cablear mientras el código de la sesión 2 no esté publicado: un
# input apuntando a un commit sin flake.nix rompe la evaluación de TODA la
# configuración, no sólo de este módulo.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.sisar.scheduler;

  toml = pkgs.formats.toml { };

  # Espacio de nombres compartido de storage-nodes.nix. El root de este nodo
  # tiene que ser el nombre COMPARTIDO y no el directorio real
  # (/var/lib/sisar/jobs): es el que se guarda en jobs.work_dir y el que
  # claim_tasks compara como prefijo para preferir lo local. Con el path real,
  # los demás nodos no podrían montar lo que este escribe.
  jobsRoot = "/srv/sisar-nodes/${cfg.nodeId}/jobs";

  systemConfig = toml.generate "config.toml" {
    paths = {
      jobs_root = jobsRoot;
      archive_root = "${cfg.centralRoot}/archive";
      logs_root = "${cfg.centralRoot}/logs";
      # Adonde se copia lo que hay que conservar cuando el job termina. Está en
      # el árbol central y no en el nodo: es lo que sobrevive cuando el
      # colector libera el directorio de trabajo, y de acá lo sirve la API.
      results_root = "${cfg.centralRoot}/results";
    };

    database = {
      url = cfg.databaseUrl;
      pool_size = cfg.databasePoolSize;
    };

    scheduler = {
      poll_interval_secs = cfg.pollIntervalSecs;
      max_concurrent_containers = cfg.maxConcurrentContainers;
      node_id = cfg.nodeId;
      lease_secs = cfg.leaseSecs;
      heartbeat_secs = cfg.heartbeatSecs;
      max_tasks_per_claim = cfg.maxTasksPerClaim;
    };

    storage = {
      min_free_gb = cfg.storage.minFreeGb;
      placement_timeout_secs = cfg.storage.placementTimeoutSecs;
      max_placements_per_poll = cfg.storage.maxPlacementsPerPoll;
    };

    resources = {
      total_cpu_cores = cfg.resources.cpuCores;
      total_ram_gb = cfg.resources.ramGb;
    };

    oom = {
      max_retries = cfg.oom.maxRetries;
      ram_multiplier = cfg.oom.ramMultiplier;
      max_stage_ram_gb = cfg.oom.maxStageRamGb;
    };

    containers = {
      # 1000:3000 = sisar:sisar-data (modules/admins.nix). Las imágenes no
      # declaran USER, así que sin esto corren como root — y el árbol central
      # se exporta con root_squash, que mapea root a nobody: cada escritura
      # falla con EACCES sin importar los permisos del directorio.
      user = "1000:3000";
      inherit (cfg.images) download isce2 mintpy miaplpy results;
    } // lib.optionalAttrs (cfg.netrcFile != null) { netrc_file = cfg.netrcFile; }
      // lib.optionalAttrs (cfg.cdsapircFile != null) { cdsapirc_file = cfg.cdsapircFile; };

    user_tiers = cfg.userTiers;
  };

  workflowConfig = toml.generate "workflows.toml" cfg.workflows;
in
{
  options.services.sisar.scheduler = {
    enable = lib.mkEnableOption "el scheduler de SISAR en este nodo";

    package = lib.mkOption {
      type = lib.types.package;
      description = ''
        El paquete que trae el binario `sisar-scheduler`. Sin default: viene
        del repo sisar-server, que se publica por separado. Ver el comentario
        al principio de este módulo.
      '';
    };

    nodeId = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
      description = ''
        Identifica a este scheduler en `jobs.claimed_by` y `tasks.claimed_by`, y
        elige qué root de storage-nodes.nix es "el propio". El hostname sirve
        salvo que corran dos schedulers en la misma máquina.
      '';
    };

    centralRoot = lib.mkOption {
      type = lib.types.str;
      default = "/srv/sisar";
      description = "Raíz del árbol central: archive/, logs/, results/.";
    };

    databaseUrl = lib.mkOption {
      type = lib.types.str;
      example = "postgres://sisar@sisar-server/sisar";
      description = ''
        Cadena de conexión a PostgreSQL. Queda en el store, que es legible por
        todo el sistema: usar autenticación por peer/ident o .pgpass, nunca una
        contraseña acá.
      '';
    };

    databasePoolSize = lib.mkOption {
      type = lib.types.int;
      default = 10;
    };

    pollIntervalSecs = lib.mkOption {
      type = lib.types.int;
      default = 10;
    };

    maxConcurrentContainers = lib.mkOption {
      type = lib.types.int;
      default = 16;
    };

    leaseSecs = lib.mkOption {
      type = lib.types.int;
      default = 90;
      description = ''
        Cuánto vale un lease sin heartbeat. Es el retardo antes de que el
        trabajo de un nodo muerto vuelva a estar disponible, pero también la
        ventana en la que un nodo lento puede perder trabajo que sigue
        corriendo. Varias veces `heartbeatSecs`.
      '';
    };

    heartbeatSecs = lib.mkOption {
      type = lib.types.int;
      default = 30;
    };

    maxTasksPerClaim = lib.mkOption {
      type = lib.types.int;
      default = 8;
    };

    storage = {
      minFreeGb = lib.mkOption {
        type = lib.types.float;
        default = 200.0;
        description = ''
          Espacio libre que este nodo se reserva antes de aceptar el
          almacenamiento de un job nuevo.

          Los nodos todavía no tienen disco de datos propio: jobs/ está en el
          disco de sistema, así que llenarlo se lleva puesto al nodo entero y
          no sólo al job. Bajar esto es tentador y caro.
        '';
      };

      placementTimeoutSecs = lib.mkOption {
        type = lib.types.int;
        default = 86400;
        description = ''
          Cuánto espera un job a que ALGÚN nodo tome su almacenamiento antes de
          fallar con `no_storage`. Es lo que hace visible a un cluster sin
          lugar, en vez de dejar jobs encolados para siempre.
        '';
      };

      maxPlacementsPerPoll = lib.mkOption {
        type = lib.types.int;
        default = 2;
      };
    };

    resources = {
      cpuCores = lib.mkOption {
        type = lib.types.int;
        description = "Presupuesto de CPU de este nodo para contenedores.";
      };
      ramGb = lib.mkOption {
        type = lib.types.float;
        description = ''
          Presupuesto de RAM en GB. Suele ser el límite real: revisar contra
          los valores de tier en workflows.toml, porque una tarea medium que
          reserva 16 GB en un nodo de 16 GB significa un contenedor por vez.
        '';
      };
    };

    oom = {
      maxRetries = lib.mkOption {
        type = lib.types.int;
        default = 2;
      };
      ramMultiplier = lib.mkOption {
        type = lib.types.float;
        default = 1.5;
      };
      maxStageRamGb = lib.mkOption {
        type = lib.types.float;
        default = 0.0;
        description = "0 = techo en `resources.ramGb`.";
      };
    };

    images = {
      download = lib.mkOption {
        type = lib.types.str;
        default = "sisar/download:0.2.0";
      };
      isce2 = lib.mkOption {
        type = lib.types.str;
        default = "sisar/isce2:0.2.0";
      };
      mintpy = lib.mkOption {
        type = lib.types.str;
        default = "sisar/mintpy:0.2.0";
      };
      miaplpy = lib.mkOption {
        type = lib.types.str;
        default = "sisar/miaplpy:0.2.0";
      };
      results = lib.mkOption {
        type = lib.types.str;
        default = "sisar/results:0.2.0";
      };
    };

    netrcFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Ruta en el host a un .netrc de Earthdata, montado read-only en cada
        contenedor. Fuera del store a propósito: el store es legible por
        cualquiera. Tiene que ser legible por el gid 3000.
      '';
    };

    cdsapircFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Ídem para .cdsapirc (Copernicus CDS, ERA5 de MintPy).";
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
      description = "Límites por tier. 0 = sin límite. Deben coincidir con los del API server.";
    };

    workflows = lib.mkOption {
      type = toml.type;
      default = {
        tiers = {
          light = {
            cpu_cores = 2;
            ram_gb = 4.0;
          };
          medium = {
            cpu_cores = 4;
            ram_gb = 12.0;
          };
          heavy = {
            cpu_cores = 8;
            ram_gb = 24.0;
          };
        };
        download = {
          cpu_cores = 2;
          ram_gb = 4.0;
        };
      };
      description = ''
        Contenido de workflows.toml. Los valores de tier describen UNA tarea, no
        una etapa entera: el scheduler reserva por tarea y multiplica por
        cuántas mete en el contenedor.
      '';
    };

    logLevel = lib.mkOption {
      type = lib.types.str;
      default = "info";
      description = "Valor de RUST_LOG.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.virtualisation.docker.enable;
        message = "services.sisar.scheduler necesita Docker: el scheduler no hace el trabajo, lo corre en contenedores.";
      }
    ];

    systemd.services.sisar-scheduler = {
      description = "SISAR scheduler (nodo ${cfg.nodeId})";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network-online.target"
        "docker.service"
      ];
      wants = [ "network-online.target" ];
      requires = [ "docker.service" ];

      # Sin esto el scheduler puede arrancar antes de los montajes y escribir
      # los directorios de job bajo un mountpoint vacío — es decir, en el disco
      # de sistema, invisibles para los demás nodos. Mismo criterio que
      # nfs-server.nix con /srv/sisar.
      unitConfig.RequiresMountsFor = [
        jobsRoot
        cfg.centralRoot
      ];

      environment = {
        SCHEDULER_CONFIG = "${systemConfig}";
        SCHEDULER_WORKFLOW_CONFIG = "${workflowConfig}";
        RUST_LOG = cfg.logLevel;
      };

      serviceConfig = {
        ExecStart = "${cfg.package}/bin/sisar-scheduler";
        User = "sisar";
        Group = "sisar";
        # Para hablar con el socket del daemon. Es acceso equivalente a root
        # sobre la máquina, y es inherente a correr contenedores desde acá.
        SupplementaryGroups = [
          "docker"
          "sisar-data"
        ];

        # Sale distinto de cero si no llega a la base; reiniciar es lo correcto
        # para aguantar un hipo de PostgreSQL.
        Restart = "always";
        RestartSec = 10;

        # El proceso arranca contenedores y escribe en NFS; el sandbox se queda
        # en lo que no le estorba.
        NoNewPrivileges = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
      };
    };
  };
}
