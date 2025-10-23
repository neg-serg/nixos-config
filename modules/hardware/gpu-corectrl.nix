{ lib, pkgs, config, ... }:
let
  cfg = config.hardware.gpu.corectrl or {};
in {
  options.hardware.gpu.corectrl = {
    enable = lib.mkEnableOption "Install CoreCtrl and allow GPU power/voltage control via polkit.";

    group = lib.mkOption {
      type = lib.types.str;
      default = "wheel";
      description = "System group whose members may use the CoreCtrl helper (polkit).";
      example = "corectrl";
    };

    ppfeaturemask = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional amdgpu.ppfeaturemask kernel parameter value to unlock OC/UV features (null = don't set).";
      example = "0xffffffff";
    };
  };

  config = lib.mkIf (cfg.enable or false) {
    environment.systemPackages = [ pkgs.corectrl ];

    # Polkit rule to allow the helper for selected group
    environment.etc."polkit-1/rules.d/60-corectrl.rules".text = ''
      polkit.addRule(function(action, subject) {
        if (action && action.id && action.id.indexOf("org.corectrl.helper") === 0 && subject.isInGroup("${cfg.group}")) {
          return polkit.Result.YES;
        }
      });
    '';

    # Optionally unlock more controls
    boot.kernelParams = lib.optionals (cfg.ppfeaturemask != null) ["amdgpu.ppfeaturemask=${cfg.ppfeaturemask}"];
  };
}

