# sisar-cluster.nix — lo que vale para TODA la flota, en un solo lugar.
#
# Datos, no un módulo: lo leen tanto modules/sisar-node.nix (los schedulers)
# como modules/sisar-master.nix (el API server). Ese es el punto — `userTiers`
# y la imagen de resultados tienen que coincidir entre el servidor y los nodos,
# y hasta ahora eran dos declaraciones separadas con un comentario pidiendo que
# no divergieran. Acá son una sola.
#
# Para cambiar algo de toda la flota se toca este archivo y se despliega. Lo que
# es genuinamente por nodo — `resources`, y `storage.minFreeGb` si ese nodo
# tiene otro disco — vive en hosts/<nodo>/default.nix.
{
  # Dirección de la base. Sin contraseña: va en ~/.pgpass del usuario sisar.
  databaseUrl = "postgres://sisar@sisar-server/sisar";

  centralRoot = "/srv/sisar";

  # Credenciales, fuera del store, root:sisar-data 0640 en cada nodo.
  netrcFile = "/etc/sisar/netrc";
  cdsapircFile = "/etc/sisar/cdsapirc";

  # Etiquetas de imagen. Tienen que ser las que están construidas en los nodos.
  images = {
    download = "sisar/download:0.2.0";
    isce2 = "sisar/isce2:0.2.0";
    mintpy = "sisar/mintpy:0.2.0";
    miaplpy = "sisar/miaplpy:0.2.0";
    results = "sisar/results:0.2.0";
  };

  # Límites por tier de usuario. El servidor los aplica al aceptar el job; el
  # scheduler usa max_concurrent_jobs al despachar. TIENEN que coincidir, y por
  # eso se declaran una sola vez.
  userTiers = {
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

  # Contenido de workflows.toml.
  #
  # Los valores de tier describen UNA tarea, no una etapa entera. Qué tier le
  # toca a cada etapa está compilado en shared/src/models.rs (resource_tier());
  # acá se define cuánto cuesta cada tier, y los overrides por etapa escapan del
  # tier para una sola.
  #
  # Ojo con la relación contra resources.ramGb de los nodos: con medium en
  # 12 GB y nodos de 16 GB entra UNA tarea medium por nodo.
  workflows = {
    tiers = {
      light = {
        cpu_cores = 1;
        ram_gb = 3.0;
      };
      medium = {
        cpu_cores = 1;
        ram_gb = 3.0;
      };
      heavy = {
        cpu_cores = 1;
        ram_gb = 3.0;
      };
    };

    download = {
      cpu_cores = 1;
      ram_gb = 3.0;
    };
    results = {
      cpu_cores = 1;
      ram_gb = 3.0;
    };

    # Overrides por etapa. Ganan sobre el tier. Las claves son el nombre de la
    # etapa en snake_case, igual que las variantes del enum.
    isce2_overrides = {
      # Ejemplo, comentado: bajar pairs_misreg para que entren dos por nodo.
      # Los números de tier son provisionales y nadie midió el pico real —
      # medir antes de bajarlos, o el OOM killer lo mide por vos.
      pairs_misreg = { cpu_cores = 1; ram_gb = 3.0; };
    };
    mintpy_overrides = { };
    miaplpy_overrides = { };
  };
}
