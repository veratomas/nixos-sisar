# RustDesk (escritorio remoto) — SÓLO para sisar-nfs.
#
# Requiere entorno gráfico, así que se importa junto con plasma6.nix.
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
{
  environment.systemPackages = with pkgs; [
    unstable.rustdesk-flutter
  ];

  # Puertos para acceso directo por IP en la LAN (sin servidor de rendezvous).
  # El imprescindible es el 21118/TCP; el resto cubre el descubrimiento y el
  # relay si más adelante levantan un servidor propio.
  networking.firewall = {
    allowedTCPPortRanges = [
      {
        from = 21115;
        to = 21119;
      }
    ];
    allowedUDPPorts = [ 21116 ];
  };

  # Recordatorio: en RustDesk hay que activar a mano
  # Configuración -> Seguridad -> "Habilitar acceso directo por IP",
  # y fijar una contraseña permanente. Si no, el cliente sólo acepta
  # conexiones vía servidor de RustDesk usando el ID.
}
