{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.features.dev.openxr or { };
  devEnabled = config.features.dev.enable or false;
  enabled = devEnabled && (cfg.enable or false);
  packages = lib.concatLists [
    (lib.optionals (cfg.envision.enable or false) [ pkgs.envision ]) # OpenXR UI for managing VR runtimes
    (lib.optionals (cfg.runtime.enable or false) [ pkgs.monado ]) # open source OpenXR runtime
    (lib.optionals (cfg.runtime.vulkanLayers.enable or false) [ pkgs."monado-vulkan-layers" ]) # Monado Vulkan layers
    (lib.optionals (cfg.tools.motoc.enable or false) [ pkgs.motoc ]) # Monado tool for configuration
    (lib.optionals (cfg.tools.basaltMonado.enable or false) [ pkgs."basalt-monado" ]) # Basalt visual-inertial SLAM for Monado
  ];
in
{
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter packages;

    services.monado = {
      enable = cfg.runtime.service.enable or false;
      defaultRuntime = true;
    };

    environment.variables = {
      # Enable SteamVR Lighthouse driver for Valve Index
      STEAMVR_LH_ENABLE = "true";
      # Force OpenXR runtime to Monado (just in case)
      XR_RUNTIME_JSON = "/run/current-system/sw/share/openxr/1/openxr_monado.json";
    };
  };
}
