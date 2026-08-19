# SSH para toda la flota, pensado para uso en red local.
{
  config,
  pkgs,
  lib,
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
  # colmena se conecta como el usuario `sisar` (deployment.targetUser en
  # flake.nix) de forma NO interactiva: necesita clave pública, no contraseña,
  # y sudo sin prompt para activar la generación.
  #
  # PONÉ ACÁ tu clave pública (la de la máquina desde la que corrés colmena):
  #   cat ~/.ssh/id_ed25519.pub
  users.users.sisar.openssh.authorizedKeys.keys = [
    # "ssh-ed25519 AAAA... usuario@equipo"
  ];

  # Alternativa: desplegar como root (targetUser = "root" en flake.nix). En ese
  # caso hace falta la clave acá y NO hace falta la regla de sudo de abajo.
  # users.users.root.openssh.authorizedKeys.keys = [
  #   "ssh-ed25519 AAAA... usuario@equipo"
  # ];

  security.sudo.extraRules = [
    {
      users = [ "sisar" ];
      commands = [
        {
          command = "ALL";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

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
