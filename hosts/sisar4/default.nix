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
    # Disco de datos: WD8006FFBX (serie C800SHKV), instalado el 2026-10-27.
    ../../modules/disco-nodo.nix
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
    # 500 como el resto de la flota: jobs/ es el disco de datos de 7,3T
    # (disco-nodo.nix). Antes este nodo no tenía disco propio y el piso era lo
    # que le impedía reclamar almacenamiento sobre el disco de sistema.
    storage.minFreeGb = 500.0;

    # Credenciales fuera del store, legibles por el gid 3000 (sisar-data).
    netrcFile = "/etc/sisar/netrc";
    cdsapircFile = "/etc/sisar/cdsapirc";
  };

  boot.loader.grub.enable = true;
  # Por id y no por letra: con el disco de datos enchufado las letras se
  # mueven entre reboots (ver disco-nodo.nix), y /dev/sda podría terminar
  # siendo el disco de datos.
  boot.loader.grub.device = "/dev/disk/by-id/ata-KINGSTON_SA400S37240G_50026B7283003089";
  boot.loader.grub.useOSProber = true;

  system.stateVersion = "25.11";
}
