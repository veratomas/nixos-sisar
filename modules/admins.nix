{
  config,
  pkgs,
  lib,
  ...
}:
{
  users.users = {
    sisar = {
      shell = pkgs.nushell;
      isNormalUser = true;
      description = "SISAR";
      # UID/GID fijos e iguales en los 6 hosts: imprescindible para que los
      # permisos del share NFS sean coherentes en toda la flota.
      uid = 1000;
      group = "sisar";
      extraGroups = [
        "networkmanager"
        "wheel"
        "lp"
        "docker"
        "sisar-data"
      ];
    };
  };

  users.groups.sisar.gid = 1000;

  # Grupo compartido para los datos exportados por NFS.
  users.groups.sisar-data.gid = 3000;

  # Las claves de despliegue (colmena) se declaran en flake.nix -> deployKeys
  # y se autorizan en modules/ssh.nix.
}
