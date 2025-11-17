{
  lib,
  pkgs,
  config,
  xdg,
  systemdUser,
  ...
}: let
  cfg = config.features.dev.openxr or {};
in {
  options.features.dev.openxr = {
    enable = (lib.mkEnableOption "enable OpenXR development stack") // {default = false;};
    envision.enable = (lib.mkEnableOption "install Envision (UI for building/configuring/running Monado)") // {default = true;};
    runtime = {
      enable = (lib.mkEnableOption "install Monado OpenXR runtime") // {default = true;};
      vulkanLayers.enable = (lib.mkEnableOption "install Monado Vulkan layers") // {default = true;};
      service.enable = (lib.mkEnableOption "run monado-service as a user systemd service (graphical preset)") // {default = false;};
    };
    tools = {
      motoc.enable = (lib.mkEnableOption "install motoc (Monado Tracking Origin Calibration)") // {default = true;};
      # Useful when experimenting with inside‑out 6DoF via cameras+IMU (DIY/unsupported HMDs). Not needed for
      # headsets that already provide reliable tracking.
      basaltMonado.enable = (lib.mkEnableOption "install basalt-monado tools (optional)") // {default = false;};
    };
  };

  config = lib.mkIf cfg.enable (
    let
      packages = lib.concatLists [
        (lib.optionals (cfg.envision.enable or false) [pkgs.envision])
        (lib.optionals (cfg.runtime.enable or false) [pkgs.monado])
        (lib.optionals (cfg.runtime.vulkanLayers.enable or false) [pkgs."monado-vulkan-layers"])
        (lib.optionals (cfg.tools.motoc.enable or false) [pkgs.motoc])
        (lib.optionals (cfg.tools.basaltMonado.enable or false) [pkgs."basalt-monado"])
      ];
      configExample = ''
        // Monado user configuration (example).
        // Rename to config.json to activate and adjust per your hardware.
        // See: https://monado.freedesktop.org/ and `man monado`.
        {
          // Minimal logging example; most setups work without a user config.
          "settings": { "log": { "level": "info" } }
        }
      '';
      basaltExample = ''
        // Basalt + Monado example (inside-out 6DoF via cameras + IMU).
        // Requires: features.dev.openxr.tools.basaltMonado.enable = true; proper camera/IMU calibration.
        // Rename to config.json after editing device names and paths below.
        {
          "drivers": {
            "basalt": {
              "enable": true,
              // Replace with your camera node(s) and parameters
              "cams": [ { "name": "/dev/video0", "resolution": [1280, 720], "fps": 60 } ],
              // Replace with your IMU identifier
              "imu": "icm20602",
              // Provide valid calibration files (intrinsics/extrinsics)
              "calibration": {
                "intrinsics": "${config.xdg.configHome}/monado/calib/intrinsics.yaml",
                "cam_to_imu": "${config.xdg.configHome}/monado/calib/cam_to_imu.yaml"
              }
            }
          }
        }
      '';
    in
      lib.mkMerge [
        {home.packages = config.lib.neg.pkgsList packages;}
        (xdg.mkXdgText "monado/config.example.jsonc" configExample)
        (xdg.mkXdgText "monado/basalt.config.example.jsonc" basaltExample)
        (lib.mkIf (cfg.runtime.service.enable or false) {
          systemd.user.services.monado-service = lib.mkMerge [
            {
              Unit = {Description = "Monado OpenXR Runtime Service";};
              Service.ExecStart = let exe = lib.getExe' pkgs.monado "monado-service"; in "${exe}";
            }
            (systemdUser.mkUnitFromPresets {presets = ["graphical"];})
          ];
        })
        {
          assertions = [
            {
              assertion = (! (cfg.runtime.service.enable or false)) || (cfg.runtime.enable or false);
              message = "features.dev.openxr.runtime.service.enable requires features.dev.openxr.runtime.enable = true";
            }
          ];
        }
      ]
  );
}
