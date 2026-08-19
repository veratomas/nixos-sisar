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

  # Clave para despliegues automatizados (colmena) como root.
  # PermitRootLogin = "prohibit-password" en ssh.nix ya exige clave, no
  # contraseña, así que sólo hace falta declarar la(s) clave(s) pública(s)
  # de la(s) máquina(s) desde donde se corre `colmena apply`.
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFgUEHxFZK5oe0F58NmBlbNTd51L3mWBlQoRdoutdTxr isatcediac@gmail.com"
  ];
}
