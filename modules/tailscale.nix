{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
{
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "client";
  };

  # Use nftables backend
  networking.nftables.enable = true;

  networking.firewall = {
    enable = true;
    trustedInterfaces = [ "tailscale0" ];
    allowedUDPPorts = [ 41641 ];
    # Fix for exit node / reverse path issues
    checkReversePath = "loose";
  };
  # Se quitó el puerto TCP 21118 (era de RustDesk, ya eliminado).

  # Force tailscaled to use nftables (avoids iptables-compat layer)
  systemd.services.tailscaled.serviceConfig.Environment = [
    "TS_DEBUG_FIREWALL_MODE=nftables"
  ];

  systemd.network.wait-online.enable = false;
  boot.initrd.systemd.network.wait-online.enable = false;
}
