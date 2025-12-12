{
  pkgs,
  config,
  lib,
  ...
}: let
  cfg = config.features.gui.enable or false;
in {
  config = lib.mkIf cfg {
    programs.wrapper-manager.enable = true;

    programs.wrapper-manager.wrappers = {
      # Nextcloud wrapper with GPU disabled to prevent crashes
      nextcloud = {
        basePackage = pkgs.nextcloud-client;
        flags = [
          "--disable-gpu"
          "--disable-software-rasterizer"
        ];
        env = {
          QTWEBENGINE_DISABLE_GPU.value = "1";
          QTWEBENGINE_CHROMIUM_FLAGS.value = "--disable-gpu --disable-software-rasterizer";
        };
      };

      # Pyprland Client wrapper
      pypr-client = {
        basePackage = pkgs.pyprland;
        # Rename the binary from pypr to pypr-client to match old script
        # Actually wrapper-manager creates a wrapper named 'pypr-client' that calls basePackage binary
        # We need to specify the target binary if it differs?
        # By default it wraps the main binary.
        # But we want 'pypr-client' command to exist.
      };
    };
  };
}
