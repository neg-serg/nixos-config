##
# Module: system/net
# Purpose: Base networking config (iwd, networkd, CLI tools).
# Key options: none (hostName/udev/bridges live under hosts/*).
# Dependencies: Imports submodules nscd/pkgs/proxy/ssh/vpn.
{lib, ...}: let
  here = ./.;
  entries = builtins.readDir here;
  importables =
    lib.mapAttrsToList (
      name: type: let
        path = here + "/${name}";
      in
        if type == "regular" && lib.hasSuffix ".nix" name && name != "default.nix"
        then path
        else if type == "directory" && builtins.pathExists (path + "/default.nix")
        then path
        else null
    )
    entries;
  imports = lib.filter (p: p != null) importables;
in {
  inherit imports;
  # Base network services; host-specific NIC rules are moved under hosts/*
  services = {};
  networking = {
    wireless.iwd.enable = true; # iwctl to manage wifi
    wireless.iwd.settings = {
      Settings = {AutoConnect = false;};
    };
    hosts = {
      "127.0.0.1" = ["localhost"];
      "::1" = ["localhost"];
    };
    useNetworkd = true;
  };

  # Packages moved to ./pkgs.nix

  systemd.network = {
    enable = true;
    # Do not block boot on wait-online; services should avoid network-online.target unless truly needed
    wait-online.enable = false;
    wait-online.anyInterface = true;
  };
}
