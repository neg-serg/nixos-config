{
  lib,
  config,
  pkgs,
  ...
}: let
  enabled = config.features.secrets.enable or true;
  packages = [
    pkgs.yubikey-agent # ssh-agent replacement that offloads keys to YubiKey
    pkgs.yubikey-manager # CLI/GUI to configure slots, certificates, OTP
    pkgs.yubikey-personalization # low-level tool for programming OTP slots
  ];
in {
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
