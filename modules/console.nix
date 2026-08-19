# Herramientas de consola, comunes a TODOS los hosts.
#
# Los "apagados" de entorno gráfico usan lib.mkDefault a propósito: así el host
# que necesite escritorio (sisar-nfs, ver modules/plasma6.nix) puede activarlo
# con una definición normal, sin necesidad de lib.mkForce y sin que el módulo
# genere un conflicto de definiciones.
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
{
  environment.systemPackages = with pkgs; [
    nushell
    oh-my-posh
    fastfetch
  ];

  # Consola TTY
  console = {
    earlySetup = true;
    keyMap = "us";
  };

  # Sin servidor X, gestor de pantalla ni escritorio (salvo override por host).
  services.xserver.enable = lib.mkDefault false;
  services.displayManager.sddm.enable = lib.mkDefault false;
  services.desktopManager.plasma6.enable = lib.mkDefault false;

  # Sin audio (salvo override por host).
  services.pulseaudio.enable = lib.mkDefault false;
  services.pipewire.enable = lib.mkDefault false;

  # Nota: no se activa environment.noXlibs a propósito: forzaría recompilar
  # medio nixpkgs sin caché binaria.
}
