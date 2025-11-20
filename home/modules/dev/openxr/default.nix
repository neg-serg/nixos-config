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
  config = lib.mkIf cfg.enable (
    let
      # Runtime/tool packages now handled via modules/dev/openxr/default.nix.
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
