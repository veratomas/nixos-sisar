# Conjunto de módulos comunes a TODOS los hosts (sisar1..sisar5 y sisar-nfs).
{ ... }:
{
  imports = [
    ./unstable.nix
    ./common.nix
    ./console.nix
    ./clitools.nix
    ./networking.nix
    ./hosts-lan.nix
    ./ssh.nix
    ./admins.nix
    ./users.nix
    ./locale.nix
    ./postgresql.nix
    ./software.nix
    ./python.nix
    ./rust.nix
    ./tailscale.nix
  ];
}
