# SSH para toda la flota, pensado para uso en red local.
{
  config,
  pkgs,
  lib,
  deployKeys,
  ...
}:
{
  services.openssh = {
    enable = true;
    ports = [ 22 ];
    openFirewall = true;
    settings = {
      PasswordAuthentication = true;
      KbdInteractiveAuthentication = false;
      AllowUsers = [
        "sisar"
        "tvera"
        "bpalazzo"
        "root" # opcional: sólo si preferís desplegar como root (ver abajo)
      ];
      UseDns = true;
      X11Forwarding = false; # sin entorno gráfico
      PermitRootLogin = "prohibit-password";
    };
  };

  # --- Acceso para colmena -------------------------------------------------
  #
  # colmena se conecta como root (deployment.targetUser en flake.nix) de forma
  # NO interactiva: necesita clave pública, nunca contraseña.
  #
  # Las claves se definen en flake.nix (`deployKeys`) y llegan por specialArgs,
  # así hay una sola fuente de verdad.
  users.users.root.openssh.authorizedKeys.keys = deployKeys;

  # Alternativa: desplegar como `sisar` (targetUser = "sisar" en flake.nix).
  # Requiere autorizar la clave para ese usuario Y sudo sin contraseña, porque
  # colmena escala privilegios con `sudo -H --` para activar la generación.
  #
  # users.users.sisar.openssh.authorizedKeys.keys = deployKeys;
  #
  # security.sudo.extraRules = [
  #   {
  #     users = [ "sisar" ];
  #     commands = [
  #       {
  #         command = "ALL";
  #         options = [ "NOPASSWD" ];
  #       }
  #     ];
  #   }
  # ];

  # Cliente SSH: alias cómodos para moverse entre nodos de la LAN.
  programs.ssh.extraConfig = ''
    Host sisar1 sisar2 sisar3 sisar4 sisar5 sisar-nfs
      User sisar
      ForwardX11 no
  '';

  # mosh: sesiones SSH que sobreviven cortes de red (abre sus puertos UDP solo).
  programs.mosh.enable = true;

  environment.systemPackages = with pkgs; [
    rsync
  ];
}
