# El scheduler de un nodo de cómputo.
#
# Trae el módulo del flake de SISAR y le aplica todo lo que vale para la flota,
# desde sisar-cluster.nix. Un host sólo declara lo que es suyo:
#
#   imports = [ ../../modules/sisar-node.nix ];
#   services.sisar.scheduler = {
#     enable = true;
#     resources = { cpuCores = 8; ramGb = 16.0; };
#   };
#
# Todo se define con mkDefault, así que un nodo puede apartarse de la flota
# cuando hace falta — un nodo con otro disco y otro minFreeGb, por ejemplo —
# sin que deje de haber un solo lugar donde está el valor común.
#
# `images`, `userTiers` y `workflows` son los que conviene NO apartar: el
# servidor y los nodos tienen que coincidir en los dos primeros, y que
# workflows.toml resuelva al mismo path del store en los seis hosts es lo que
# hace visible que la flota está de acuerdo sobre lo que cuesta cada etapa.
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
  imports = [ inputs.sisar.nixosModules.scheduler ];

  services.sisar.scheduler = {
    package = lib.mkDefault inputs.sisar.packages.x86_64-linux.sisar-scheduler;

    databaseUrl = lib.mkDefault cluster.databaseUrl;
    centralRoot = lib.mkDefault cluster.centralRoot;

    netrcFile = lib.mkDefault cluster.netrcFile;
    cdsapircFile = lib.mkDefault cluster.cdsapircFile;

    images = lib.mapAttrs (_: v: lib.mkDefault v) cluster.images;

    userTiers = lib.mkDefault cluster.userTiers;
    workflows = lib.mkDefault cluster.workflows;
  };
}
