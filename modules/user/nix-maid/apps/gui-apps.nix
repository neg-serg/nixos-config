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
        # Chromium-family apps (Vivaldi) shell out to zenity/kdialog/xmessage
        # for the "profile is in use" dialog. With none of them installed the
        # dialog cannot be shown and the browser just exits silently on a stale
        # SingletonLock.
        pkgs.zenity # GTK dialog tool Chromium uses for profile-in-use prompts
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
