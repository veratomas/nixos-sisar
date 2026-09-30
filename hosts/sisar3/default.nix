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
    ../../modules/disco-nodo.nix
    ../../modules/storage-nodes.nix
    ../../modules/sisar-node.nix
  ];

  networking.hostName = "sisar3";

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
    # 500 como sisar1 y sisar2. Estaba en 50 porque jobs/ vivía en el disco de
    # sistema (219G), donde un piso de 500 no se alcanza nunca; ahora jobs/ es
    # el disco de datos de 7,3T (disco-nodo.nix) y el valor de la flota aplica.
    storage.minFreeGb = 500.0;

    # Credenciales fuera del store, legibles por el gid 3000 (sisar-data).
    netrcFile = "/etc/sisar/netrc";
    cdsapircFile = "/etc/sisar/cdsapirc";
  };


  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  system.stateVersion = "25.11";
}
