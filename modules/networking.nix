{
  config,
  pkgs,
  lib,
  ...
}:
{
  networking.networkmanager.enable = true;

  # Firewall activo; SSH abierto (ver ssh.nix para el resto de la config).
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
  };
}
