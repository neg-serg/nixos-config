{
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = config.features.dev.openxr or {};
  devEnabled = config.features.dev.enable or false;
  enabled = devEnabled && (cfg.enable or false);
  packages = lib.concatLists [
    (lib.optionals (cfg.envision.enable or false) [pkgs.envision])
    (lib.optionals (cfg.runtime.enable or false) [pkgs.monado])
    (lib.optionals (cfg.runtime.vulkanLayers.enable or false) [pkgs."monado-vulkan-layers"])
    (lib.optionals (cfg.tools.motoc.enable or false) [pkgs.motoc])
    (lib.optionals (cfg.tools.basaltMonado.enable or false) [pkgs."basalt-monado"])
  ];
in {
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
