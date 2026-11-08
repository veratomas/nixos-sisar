# Docker — en TODOS los hosts.
#
# Vivía dentro de postgresql.nix, que ahora sólo se importa en sisar-server. Se
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

  # Que reiniciar dockerd no mate los contenedores. Con stateVersion 25.11 el
  # default es false, y cualquier cambio en daemon.json (que va en el
  # ExecStart) reinicia dockerd al activar: un deploy así se llevaba puestas
  # todas las tareas en curso. Este mismo cambio es el último reinicio que las
  # mata.
  virtualisation.docker.daemon.settings.live-restore = true;
}
