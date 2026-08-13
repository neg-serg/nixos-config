{
  lib,
  mkBool,
  ...
}:
with lib;
{
  options.features = {
    hardware = {
      bluetooth.enable = mkBool "enable Bluetooth support" false;

      usbAutomount.enable = lib.mkEnableOption ''
        Enable udev-driven USB storage auto-mount via systemd service (mounts under /mnt/<label>).
      '';
    };
    input = {
      kanata.enable = mkBool "enable Kanata keyboard remapper (requires uinput module)" false;
      warpd.enable = mkBool "enable warpd (modal keyboard-driven pointer control)" false;
    };
  };
}
