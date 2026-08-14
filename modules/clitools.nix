{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
{
  environment.systemPackages = with pkgs; [
    evil-helix
    _7zz
    file
    (yazi.override {
      _7zz = _7zz-rar; # Support for RAR extraction
    })
  ];
}
