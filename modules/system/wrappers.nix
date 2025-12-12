{
  pkgs,
  lib,
  config,
  inputs,
  ...
}: let
  cfg = config.features.gui.enable or false;
in {
  imports = [
    # Import the wrapper-manager generic module
    (inputs.wrapper-manager + "/modules/many-wrappers.nix")
  ];

  config = lib.mkIf cfg {
    # Define wrappers using the generic module options
    wrappers = {
      # Nextcloud wrapper with GPU disabled
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
      };
    };

    # Install the built wrappers into system packages
    environment.systemPackages = [
      config.build.toplevel
    ];
  };
}
