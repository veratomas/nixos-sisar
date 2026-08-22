# PostgreSQL — CLIENTE (todos los hosts).
#
# No levanta ningún servidor: sólo deja las herramientas (psql, pg_dump) y las
# variables de entorno para que cualquier proceso apunte a sisar-nfs sin
# repetir la cadena de conexión en cada script.
#
# Con esto, en cualquier nodo alcanza con `psql` a secas para entrar a la base
# compartida.
{
  config,
  pkgs,
  lib,
  ...
}:
{
  environment.systemPackages = with pkgs; [ postgresql ];

  environment.sessionVariables = {
    PGHOST = "sisar-nfs";
    PGPORT = "5432";
    PGDATABASE = "sisar";
    PGUSER = "sisar";
  };

  # La contraseña NO va acá: todo lo que se declara en un módulo termina en
  # /nix/store, que es legible por cualquier usuario del sistema. Va en el
  # ~/.pgpass de cada usuario (modo 0600) — ver la guía.
}
