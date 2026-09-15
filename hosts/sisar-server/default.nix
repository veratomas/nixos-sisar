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
    inputs.sisar.nixosModules.server

    # Único host con entorno gráfico: se usa como terminal de trabajo.
    ../../modules/plasma6.nix
    ../../modules/rustdesk.nix
  ];

  networking.hostName = "sisar-server";

  # El API server, como servicio. El paquete sale del flake de SISAR: nada acá
  # sabe de cargo, y nada apunta a ./target/release/.
  services.sisar.server = {
    enable = true;
    package = inputs.sisar.packages.x86_64-linux.sisar-server;
    listen = "0.0.0.0:8080";
    openFirewall = true;

    # Los tokens NO van en el store: este archivo lo crea el operador,
    # root-owned, y el servidor lo lee al arrancar.
    #   sudo install -o sisar -g sisar -m 600 /dev/null /etc/sisar/interface-tokens.toml
    interfaceTokensFile = "/etc/sisar/interface-tokens.toml";
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  system.stateVersion = "25.11";
}
