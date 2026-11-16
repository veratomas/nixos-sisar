# Servidor ISAT (frontend + usuarios/sesiones) detrás del nginx de sisar.com.ar.
#
# Copiar a  nixos-sisar/modules/isat.nix  e importarlo desde
# hosts/sisar-server/default.nix. Requiere el input `isat` en flake.nix.
#
# El módulo real vive en el repo de ISAT (despliegue/nix/module.nix): acá solo se
# configura, para no duplicar la definición del servicio en dos lados.
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
{
  imports = [ inputs.isat.nixosModules.default ];

  services.isat = {
    enable = true;

    # Solo loopback: el único que tiene que llegar es el nginx de este mismo
    # host, que ya hace proxy_pass en modules/nginx.nix. Exponerlo en 0.0.0.0
    # lo dejaría accesible por el tailnet sin pasar por TLS ni por el reverse
    # proxy.
    host = "127.0.0.1";

    # 8081 y no 8080: en sisar-server el 8080 ya es de `sisar-master`, la API
    # de procesamiento. Tiene que coincidir con el `backend` de
    # modules/nginx.nix.
    port = 8081;

    # No hace falta abrir nada en el firewall: al escuchar en loopback, el
    # tráfico entra por 80/443 que nginx ya tiene abiertos. (El módulo no tiene
    # una opción `openFirewall` propia: sólo `nginx.openFirewall`, que acá no
    # aplica porque `nginx.enable` es false. Declararla rompía la evaluación.)

    # El host ya tiene su nginx (modules/nginx.nix), con el virtualHost
    # "sisar.com.ar" marcado `default` y con "localhost" entre sus alias. El
    # de este módulo declararía otro vhost `default`, y nginx no arranca con
    # dos: hay que apagarlo y dejar que el del host haga el proxy.
    nginx.enable = false;

    # La página la sirve ese nginx desde /var/www/sisar/frontend. El backend
    # apunta al mismo directorio para que las dos mitades sirvan lo mismo.
    frontendDir = "/var/www/sisar/frontend";

    # Tiene que coincidir con el client_max_body_size de modules/nginx.nix
    # (500M). Si se cambia uno, cambiar el otro: si nginx permite más que el
    # backend, la subida se corta con un error confuso a mitad de camino.
    maxUploadMb = 500;

    # Dónde deja el pipeline los jobs terminados (0.4.1 en adelante): un
    # almacén Zarr por job en <id>/results/sisar.zarr. ISAT lo lee ahí mismo,
    # de sólo lectura. El pipeline exporta sólo eso: sin esta carpeta los jobs
    # nuevos no aparecen en el mapa. El usuario dinámico del servicio los lee
    # porque están abiertos al resto (r-x en carpetas, r-- en archivos).
    resultsDir = "/srv/sisar/results";

    # Sin adminPasswordFile a propósito: el servidor genera una contraseña
    # aleatoria en el primer arranque (la base arranca vacía) y la escribe en
    # el journal. Para leerla, una vez aplicado esto:
    #
    #   journalctl -u isat | grep -i admin
    #
    # Anotala, entrá con el usuario `admin` y cambiala desde el panel de
    # Usuarios. Después de eso el valor del journal deja de servir.
  };

  # Desde la v0.8 la base es el esquema `isat` de la base PostgreSQL `sisar` (la
  # de SISAR), por socket y con el rol `isat` (peer: el usuario dinámico se
  # llama igual). Antes del primer arranque, una sola vez y como `postgres`:
  # isat-server/migraciones/postgres/roles-y-permisos.sql, y si había cuentas
  # en el isat.db anterior, migrar_a_postgres (ver despliegue/nixos.md).
  #
  # Vinculación con el bot de Telegram: el token con el que el bot canjea los
  # códigos va en un archivo fuera del store (formato `telegram = "token"`).
  # services.isat.telegram = {
  #   tokensFile = "/etc/isat/tokens-interfaz.toml";
  #   botName = "@el_bot";
  # };

  # El servicio corre con DynamicUser, así que su estado vive en
  # /var/lib/private/isat con el enlace /var/lib/isat. Lo que hay que respaldar:
  #
  #   pg_dump -d sisar                   (cuentas, sesiones y metadatos: esquema isat)
  #   /var/lib/isat/interferogramas/     (los archivos subidos y sus COG)
}
