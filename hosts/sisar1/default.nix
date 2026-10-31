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
    # Disco de datos: el WD8006FFBX de reemplazo (serie C800S5TV). El primero
    # que vino para este nodo estaba fallado — no se podía leer ni el sector 0
    # — y se retiró el 2026-09-30.
    ../../modules/disco-nodo.nix
    ../../modules/storage-nodes.nix
    ../../modules/sisar-node.nix
  ];

  networking.hostName = "sisar1";

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
    storage.minFreeGb = 500.0;

    # Credenciales fuera del store, legibles por el gid 3000 (sisar-data).
    netrcFile = "/etc/sisar/netrc";
    cdsapircFile = "/etc/sisar/cdsapirc";
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  system.stateVersion = "25.11";
}
