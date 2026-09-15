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
    inputs.sisar.nixosModules.scheduler
  ];

  networking.hostName = "sisar1";

  # El scheduler de este nodo. Agregar un nodo es esto y una línea en nodes.nix.
  services.sisar.scheduler = {
    enable = true;
    package = inputs.sisar.packages.x86_64-linux.sisar-scheduler;

    databaseUrl = "postgres://sisar@sisar-server/sisar";

    # Presupuesto de este nodo para contenedores. RAM suele ser el límite real:
    # revisar contra los tiers de workflows.toml antes de subirlo.
    resources = {
      cpuCores = 8;
      ramGb = 16.0;
    };

    # Credenciales fuera del store, legibles por el gid 3000 (sisar-data).
    netrcFile = "/etc/sisar/netrc";
    cdsapircFile = "/etc/sisar/cdsapirc";
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  system.stateVersion = "25.11";
}
