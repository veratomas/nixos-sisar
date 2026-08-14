{
  config,
  pkgs,
  lib,
  ...
}:
{
  users.users = {
    tvera = {
      shell = pkgs.nushell;
      isNormalUser = true;
      description = "Tomás Vera";
      uid = 1001;
      group = "tvera";
      extraGroups = [
        "networkmanager"
        "wheel"
        "lp"
        "docker"
        "sisar-data"
      ];
    };
    bpalazzo = {
      shell = pkgs.nushell;
      isNormalUser = true;
      description = "Benjamín Palazzo";
      uid = 1002;
      group = "bpalazzo";
      extraGroups = [
        "networkmanager"
        "wheel"
        "lp"
        "docker"
        "sisar-data"
      ];
    };
  };

  users.groups.tvera.gid = 1001;
  users.groups.bpalazzo.gid = 1002;

  # La configuración de openssh (incluido AllowUsers) vive ahora en ssh.nix.
}
