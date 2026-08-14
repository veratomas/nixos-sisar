# Reemplaza a terminal.nix: sólo herramientas de consola.
# Se eliminaron kitty y xterm (emuladores de terminal gráficos).
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

  # Consola TTY (no X/Wayland)
  console = {
    earlySetup = true;
    keyMap = "us";
  };

  # Ni servidor X ni gestor de pantalla ni escritorio.
  services.xserver.enable = false;
  services.displayManager.sddm.enable = false;
  services.desktopManager.plasma6.enable = false;

  # Sin audio (no hay entorno de escritorio).
  services.pulseaudio.enable = false;
  services.pipewire.enable = false;

  # Nota: no se activa environment.noXlibs a propósito: forzaría recompilar
  # medio nixpkgs sin caché binaria. El sistema ya queda sin entorno gráfico.
}
