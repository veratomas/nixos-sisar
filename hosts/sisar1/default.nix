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
    # disco-nodo.nix: PENDIENTE, falta el disco. El WD8006FFBX que vino para
    # este nodo estaba fallado — no se podía leer ni el sector 0 ("critical
    # target error, dev sda, sector 0" en dmesg, `dd` de un bloque devolvía 0
    # bytes). Confirmado con smartctl y retirado de la máquina (2026-09-30).
    #
    # Cuando llegue el reemplazo: formatearlo como dice disco-nodo.nix
    # (etiqueta `sisar-jobs`), descomentar el import de abajo y reconstruir.
    # No hace falta tocar nada más — el resto del nodo ya está configurado
    # como sisar2 y sisar3.
    #
    # Mientras no haya disco, este nodo es de cómputo solamente, igual que
    # sisar4: aporta CPU y RAM contra el jobs/ de sisar2 y sisar3 por NFS, y no
    # reclama almacenamiento. El piso de 500 contra ~115G libres es lo que lo
    # garantiza, y está bien así — ver la nota larga en hosts/sisar4/default.nix
    # sobre por qué NO hay que bajarlo.
    #
    # ../../modules/disco-nodo.nix
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
