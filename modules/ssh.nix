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
        "root" # sólo con clave (ver PermitRootLogin abajo): lo usa colmena para desplegar
      ];
      UseDns = true;
      X11Forwarding = false; # sin entorno gráfico
      PermitRootLogin = "prohibit-password";
    };
  };

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
