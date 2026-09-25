# modules/nginx.nix
#
# Servidor web del sitio de SISAR, servido SÓLO en la LAN por ahora.
#
# `forceSSL` y `enableACME` quedan afuera A PROPÓSITO, no por olvido: falta la
# aprobación de SCL para publicar el sitio, y el dominio sisar.com.ar todavía
# no resuelve en internet (está registrado, pero sus nameservers devuelven
# REFUSED). Con el dominio así, Let's Encrypt no puede validar y el servicio
# ACME falla en cada arranque.
#
# Mientras tanto: el nombre se resuelve a mano contra la IP del servidor vía
# extraHosts y se sirve por HTTP en el 80, sólo dentro de la LAN.
#
# Cuando SCL apruebe y el dominio esté delegado de verdad: agregar
# `enableACME = true;` + `forceSSL = true;` al virtualHost, abrir el 443 en el
# firewall y sacar la entrada de extraHosts.
{ ... }:
let
  nodes = import ../nodes.nix;
  serverIp = nodes.server.sisar-server;

  # /var/www/sisar es el checkout del repo isat; el sitio estático vive en
  # frontend/ (ahí está index.html).
  webRoot = "/var/www/sisar/frontend";

  # Backend de la página (modules/isat.nix). Todo lo dinámico cuelga de /api;
  # /panel es el panel de administración, que también sirve ese proceso.
  backend = "http://127.0.0.1:8081";
in
{
  # La resolución de sisar.com.ar -> IP del servidor vive en
  # modules/hosts-lan.nix (atributo `aliases`), que se aplica a TODA la flota.
  # Acá sólo se abre el puerto: escucha en 0.0.0.0, así que cualquier equipo de
  # la LAN llega por http://${serverIp}.
  networking.firewall.allowedTCPPorts = [ 80 ];

  services.nginx = {
    enable = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;

    virtualHosts."sisar.com.ar" = {
      default = true; # también responde entrando por IP o por localhost
      serverAliases = [
        "www.sisar.com.ar"
        "localhost"
        "sisar-server"
      ];
      root = webRoot;
      locations."/".index = "index.html";

      # Las subidas de interferogramas pueden llegar a 500 MB
      # (ISAT_MAX_UPLOAD_MB); sin esto nginx corta con 413 antes de que el
      # backend vea el archivo.
      extraConfig = ''
        client_max_body_size 500m;
      '';

      locations."/api/" = {
        proxyPass = backend;
        extraConfig = ''
          proxy_request_buffering off;
          proxy_read_timeout 600s;
          proxy_send_timeout 600s;
        '';
      };

      locations."/panel" = {
        proxyPass = backend;
      };
    };
  };
}
