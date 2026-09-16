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
    ../../modules/nfs-server.nix
    ../../modules/disco-sisar.nix
    ../../modules/postgresql-server.nix
    ../../modules/sisar-master.nix

    # Único host con entorno gráfico: se usa como terminal de trabajo.
    ../../modules/plasma6.nix
    ../../modules/rustdesk.nix
  ];

  networking.hostName = "sisar-server";

  # Lo propio del servidor. userTiers y la imagen de resultados salen de
  # sisar-cluster.nix, compartidos con los nodos.
  services.sisar.server = {
    enable = true;
    listen = "0.0.0.0:8080";
    openFirewall = true;

    # Los tokens no van al store: archivo root-owned que el servidor lee al
    # arrancar. Rotar uno es editarlo y reiniciar el servicio.
    interfaceTokensFile = "/etc/sisar/interface-tokens.toml";
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  system.stateVersion = "25.11";
}
