# El API server, en sisar-server.
#
# Comparte sisar-cluster.nix con los nodos: `userTiers` y la imagen de
# resultados salen de ahí, que es la única forma de que no discrepen con lo que
# despachan los schedulers. El módulo del servidor valida los tiers al aceptar
# un job y el scheduler aplica max_concurrent_jobs al despachar: si difieren,
# un job entra y después no sale.
{
  config,
  lib,
  inputs,
  ...
}:
let
  cluster = import ../sisar-cluster.nix;
in
{
  imports = [ inputs.sisar.nixosModules.server ];

  services.sisar.server = {
    package = lib.mkDefault inputs.sisar.packages.x86_64-linux.sisar-server;

    centralRoot = lib.mkDefault cluster.centralRoot;
    userTiers = lib.mkDefault cluster.userTiers;
    resultsImage = lib.mkDefault cluster.images.results;
  };
}
