{
  lib,
  config,
  ...
}: let
  cfg = config.features.dev.openxr or {};
in {
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      # (xdg.mkXdgText "monado/config.example.jsonc" configExample)
      # (xdg.mkXdgText "monado/basalt.config.example.jsonc" basaltExample)
      # (lib.mkIf (cfg.runtime.service.enable or false) {
      #   systemd.user.services.monado-service = lib.mkMerge [
      #     {
      #       Unit = {Description = "Monado OpenXR Runtime Service";};
      #       Service.ExecStart = let exe = lib.getExe' pkgs.monado "monado-service"; in "${exe}";
      #     }
      #     (systemdUser.mkUnitFromPresets {presets = ["graphical"];})
      #   ];
      # })
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
