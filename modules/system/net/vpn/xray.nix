{ config, lib, pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.xorg.xhost # Manage X server access from nekoray UI
  ] ++ lib.optional (config.features.apps.throne.enable or false) pkgs.throne;
}
