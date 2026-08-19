# Escritorio KDE Plasma 6 — SÓLO para sisar-nfs.
#
# No se importa desde base.nix: los sisar1..sisar5 siguen headless. Este módulo
# sobrescribe los mkDefault de console.nix.
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
{
  # Sesión Wayland (por defecto) y también X11.
  # X11 se deja habilitado a propósito: RustDesk funciona sin fricción ahí,
  # mientras que bajo Wayland depende de los portales de PipeWire (ver abajo).
  services.xserver.enable = true;
  services.xserver.xkb.layout = "us";

  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };

  services.desktopManager.plasma6.enable = true;

  # Aceleración gráfica
  hardware.graphics.enable = true;

  # Audio (PipeWire, no PulseAudio)
  services.pulseaudio.enable = false;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Portales XDG: necesarios para compartir pantalla bajo Wayland
  # (captura vía PipeWire). plasma6 ya trae xdg-desktop-portal-kde.
  xdg.portal.enable = true;

  environment.systemPackages = with pkgs; [
    kitty
  ];

  fonts.packages = [
    pkgs.nerd-fonts.jetbrains-mono
    pkgs.libertinus
    pkgs.corefonts
  ];

  # La documentación se había desactivado por ser un equipo headless; con
  # escritorio vuelve a tener sentido (KHelpCenter, man pages en Konsole).
  documentation.doc.enable = true;
  documentation.nixos.enable = true;
}
