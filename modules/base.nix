# Conjunto de módulos comunes a TODOS los hosts (sisar1..sisar5 y sisar-nfs).
#
# Nota: los overlays (rust-overlay, pkgs.unstable) y nixpkgs.config ya no se
# definen en módulos, sino en flake.nix — es incompatible con colmena.
{ ... }:
{
  imports = [
    ./common.nix
    ./console.nix
    ./clitools.nix
    ./networking.nix
    ./hosts-lan.nix
    ./ssh.nix
    ./admins.nix
    ./users.nix
    ./locale.nix
    ./docker.nix
    ./postgresql-client.nix
    ./software.nix
    ./python.nix
    ./rust.nix
    ./tailscale.nix
  ];

  # postgresql.nix se dividió: el SERVIDOR se importa sólo desde
  # hosts/sisar-nfs/default.nix (postgresql-server.nix), y acá queda el
  # cliente. Antes, los seis hosts levantaban su propio PostgreSQL con una
  # base `sisar` vacía cada uno.
  #
  # Docker salió de postgresql.nix a su propio módulo: lo necesitan todos los
  # nodos para los contenedores de ISCE y descargas.
}
