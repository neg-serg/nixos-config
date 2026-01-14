##
# Module: system/net/wifi
# Purpose: Reusable Wi-Fi toggle so hosts can opt into iwd without hand-written mkForce overrides.
# Key options: config.profiles.network.wifi.enable
# Dependencies: Relies on modules/system/net/{default,pkgs}.nix to install iwd binaries/unit hooks.
{
  lib,
  config,
  ...
}:
{
  options.profiles.network.wifi.enable = lib.mkEnableOption ''
    Enable Wi-Fi management (starts iwd). Use this on hosts that need wireless networking;
    the base network module keeps iwd disabled elsewhere to avoid unnecessary units.
  '';

  config =
    lib.mkIf (config.profiles.network.wifi.enable || (config.features.net.wifi.enable or false))
      {
        # Base module hard-disables iwd to keep hosts wired-only by default; opt-in hosts force-enable it.
        networking.wireless.iwd.enable = lib.mkForce true;
      };
}
