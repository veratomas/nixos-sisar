# El API server, en sisar-server.
#
# Comparte sisar-cluster.nix con los nodos: `userTiers` y el registry de las
# imágenes salen de ahí, que es la única forma de que no discrepen con lo que
# despachan los schedulers. El módulo del servidor valida los tiers al aceptar
# un job y el scheduler aplica max_concurrent_jobs al despachar: si difieren,
# un job entra y después no sale.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cluster = import ../sisar-cluster.nix;

  dockerRoot = "/srv/sisar/docker";
in
{
  imports = [
    inputs.sisar.nixosModules.server
    inputs.sisar.nixosModules.images
  ];

  services.sisar.server = {
    package = lib.mkDefault inputs.sisar.packages.x86_64-linux.sisar-server;

    centralRoot = lib.mkDefault cluster.centralRoot;
    userTiers = lib.mkDefault cluster.userTiers;
  };

  # El registry y el build de las seis imágenes, una vez por commit de sisar.
  # Sólo los nodos de cómputo pasan el firewall hacia el registry.
  services.sisar.images = {
    enable = true;
    inherit (cluster) registry;
    builder = {
      enable = true;
      clients = builtins.attrValues (import ../nodes.nix).compute;
    };
  };

  # Docker del servidor en el disco de datos, con una política de caché propia.
  #
  # En la raíz (219 GB, con el store y PostgreSQL) quedaban ~31 GB libres, y la
  # GC de BuildKit por defecto quiere 41 GB libres: recortaba la caché a ~20 GB,
  # menos que un juego de imágenes, y cada commit reconstruía las seis en frío
  # (~2 h, y con versiones de conda nuevas). Acá la caché se queda: nunca menos
  # de 100 GB, nunca más de 300 GB, y siempre 500 GB libres en el disco.
  #
  # En el servidor Docker sólo construye: Nextcloud es un contenedor de NixOS,
  # no de Docker, y el registry es un servicio.
  virtualisation.docker.daemon.settings = {
    data-root = dockerRoot;
    builder.gc = {
      enabled = true;
      defaultReservedSpace = "100GB";
      defaultMaxUsedSpace = "300GB";
      defaultMinFreeSpace = "500GB";
    };
  };

  systemd.services.docker = {
    # Sin el disco montado, dockerd armaría una raíz nueva en el disco de
    # sistema, y lo llenaría.
    unitConfig.RequiresMountsFor = [ dockerRoot ];

    # Se crea acá, antes que dockerd, por la ACL por defecto de /srv/sisar
    # (rwx para sisar-data): heredada, cada archivo de cada capa quedaría con
    # esa entrada, visible por NFS. Lo mismo que hace nextcloud.nix.
    preStart = ''
      ${pkgs.coreutils}/bin/install -d -m 0710 -o root -g root ${dockerRoot}
      ${pkgs.acl}/bin/setfacl -b ${dockerRoot}
    '';
  };
}
