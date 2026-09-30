{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/base.nix
    ../../modules/nfs-client.nix
    ../../modules/storage-nodes.nix
    ../../modules/sisar-node.nix
  ];

  networking.hostName = "sisar4";

  # Lo único que es de este nodo. Todo lo demás — base de datos, imágenes,
  # tiers, credenciales — sale de sisar-cluster.nix vía modules/sisar-node.nix.
  services.sisar.scheduler = {
    enable = true;
    package = inputs.sisar.packages.x86_64-linux.sisar-scheduler;
    logLevel = "sisar_scheduler::scheduler=debug,shared=info";

    databaseUrl = "postgres://sisar@sisar-server/sisar";

    # Presupuesto de este nodo para contenedores. RAM suele ser el límite real:
    # con medium en 12 GB, 16 GB acá significa UNA tarea medium por vez.
    resources = {
      cpuCores = 8;
      ramGb = 16.0;
    };
    # Nodo de cómputo SIN almacenamiento propio, a propósito.
    #
    # Este host no tiene disco de datos: su jobs/ sigue en el disco de sistema,
    # con ~124G libres contra un piso de 500. O sea que NUNCA va a reclamar el
    # almacenamiento de un job, y eso es lo buscado — el almacenamiento vive en
    # los nodos que sí tienen disco grande (sisar2, sisar3), y este aporta CPU y
    # RAM trabajando contra el jobs/ de ellos por NFS.
    #
    # Que igual pueda ejecutar tareas no es casualidad: en claim_tasks la
    # localidad es un ORDER BY (`work_dir LIKE <root>%` DESC), una PREFERENCIA,
    # no un WHERE. Un nodo puede reclamar tareas de un job cuyo work_dir está en
    # otro; sólo las toma después de las locales.
    #
    # NO bajar este piso para "arreglar" que no reclama almacenamiento. Bajarlo
    # pondría jobs de cientos de GB en el disco de sistema, y llenarlo tira el
    # nodo entero, no sólo el job. Si se quiere que este nodo almacene, la
    # respuesta es un disco y disco-nodo.nix, como sisar2 y sisar3.
    storage.minFreeGb = 500.0;

    # Credenciales fuera del store, legibles por el gid 3000 (sisar-data).
    netrcFile = "/etc/sisar/netrc";
    cdsapircFile = "/etc/sisar/cdsapirc";
  };

  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda"; # verificar el disco real de este equipo
  boot.loader.grub.useOSProber = true;

  system.stateVersion = "25.11";
}
