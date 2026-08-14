{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
{
  environment.systemPackages = with pkgs; [
    python314
    typst
    tinymist
  ];
  # obsidian eliminado (aplicación Electron/GUI).
}
