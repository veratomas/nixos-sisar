{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
{
  environment.systemPackages = with pkgs; [
    (pkgs.python3.withPackages (
      ps: with ps; [
        python-telegram-bot
        python-dotenv
        httpx
        numpy
        h5py
        scipy
        matplotlib
        pyzbar
        pillow
      ]
    ))
    zbar
  ];

  # tkinter se quitó: es una toolkit gráfica y no hay X/Wayland en estos hosts.
  # matplotlib se mantiene pero forzado a backend no interactivo (guarda a archivo).
  environment.variables.MPLBACKEND = "Agg";
}
