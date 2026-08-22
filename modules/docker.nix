# Docker — en TODOS los hosts.
#
# Vivía dentro de postgresql.nix, que ahora sólo se importa en sisar-nfs. Se
# separó para que los nodos que corren los contenedores de ISCE y descargas no
# se queden sin Docker al perder el módulo de PostgreSQL.
{
  config,
  pkgs,
  lib,
  ...
}:
{
  virtualisation.docker.enable = true;
}
