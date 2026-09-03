# Driver NVIDIA — en TODOS los hosts (sisar1..sisar5 y sisar-server), todos
# con una GTX 650 (GK107, arquitectura Kepler).
#
# Kepler es la última arquitectura que soporta la rama de driver 470: NVIDIA
# la pasó a "legacy" en la serie 495+ y no va a haber drivers nuevos para
# esta placa nunca más (ver
# https://nvidia.custhelp.com/app/answers/detail/a_id/5202). Por eso
# `legacy_470` y no `stable`/`production` (esos dejan de reconocer la placa).
#
# El kernel module "open" (open-gpu-kernel-modules) NO es una opción acá:
# sólo existe desde el driver 515 en adelante y sólo para Turing+. `open =
# false` es el default, pero lo dejamos explícito para que un cambio de
# default en NixOS no rompa el build en silencio.
{
  config,
  lib,
  pkgs,
  ...
}:
{
  # Esto es lo que hace que NixOS arme el kernel module de nvidia y lo cargue
  # al boot — hace falta aunque el host sea headless (sisar1..sisar5, sin
  # xserver.enable; ver console.nix). Sin esto en videoDrivers, hardware.nvidia
  # queda declarado pero nvidia_x11 nunca se resuelve.
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.graphics.enable = true;

  hardware.nvidia = {
    modesetting.enable = true;

    package = config.boot.kernelPackages.nvidiaPackages.legacy_470;

    open = false;

    # Optimus/PRIME (powerManagement.finegrained) no aplica: son placas de
    # escritorio fijas, no hay GPU integrada con la que alternar.
    powerManagement.enable = false;

    # nvidia-settings necesita entorno gráfico; sólo sisar-server lo tiene
    # (plasma6.nix), y ese módulo ya fuerza nvidiaSettings = true si hace
    # falta. Acá, default a false para no tirar el paquete gráfico en los
    # nodos headless.
    nvidiaSettings = lib.mkDefault false;

    # nvidia-persistenced: mantiene la GPU inicializada entre jobs en vez de
    # reiniciar el estado del driver en cada `nvidia-smi`/proceso CUDA nuevo.
    # Es la recomendación estándar de NVIDIA para GPUs headless de cómputo.
    nvidiaPersistenced = true;
  };
}
