{ lib, neg, pkgs, ... }: {
  config = lib.mkMerge [
    {
      # Packages
      environment.systemPackages = [
        # Galaxy Buds manager — ANC/EQ/touchpad/battery over RFCOMM/SPP.
        # The buds are normally handed to the Questyle dongle; this app needs
        # them paired with the PC's own adapter (see modules/system/kernel for
        # CONFIG_BT_RFCOMM, which this app depends on).
        pkgs.galaxy-buds-client # unofficial Galaxy Buds manager (ANC/EQ/touchpad)
      ];
    }
    (neg.mkHomeFiles {
      # Handlr Config
      ".config/handlr/handlr.toml".text = ''
        enable_selector = false
        selector = "vicinae dmenu -p 'Open With: ❯>'"
      '';
    })
  ];
}
