{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
{
  environment.systemPackages = with pkgs; [
    openssl
    pkg-config
    gcc
    (rust-bin.stable.latest.default.override {
      targets = [
        "x86_64-unknown-linux-gnu"
        "x86_64-unknown-linux-musl"
      ];
    })
  ];
}
