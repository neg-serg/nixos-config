{
  neg,
  lib,
  config,
  ...
}:
with lib;
let
  # Child feature requires parent feature
  assertParent = parentCond: childCond: msg: {
    assertion = parentCond || (!childCond);
    message = msg;
  };
in
{
  imports = neg.importDir { dir = ./.; };

  # Apply profile defaults. Users can still override flags after this.
  config = mkMerge [
    # When dev-speed is enabled, prefer lean defaults for heavy subfeatures
    (mkIf (config.lib.neg.enabled "devSpeed") {
      features = {
        web = {
          tools.enable = mkDefault false;
        };
        gui.qt.enable = mkDefault false;
        fun.enable = mkDefault false;
        dev.ai.enable = mkDefault false;
        torrent.enable = mkDefault false;
      };
    })
    # If parent feature is disabled, default child toggles to false to avoid contradictions
    (mkIf (!config.lib.neg.enabled "web") {
      # Parent off must force-disable children to avoid priority conflicts
      features.web = {
        tools.enable = mkForce false;
      };
    })
    # When a parent feature is disabled, force-disable children to avoid priority conflicts
    (mkIf (!config.lib.neg.enabled "dev") {
      features = {
        dev = {
          ai = {
            enable = mkForce false;
          };
          rust.enable = mkForce false;
          cpp.enable = mkForce false;
        };
      };
    })
    (mkIf (!config.lib.neg.enabled "gui") {
      features = {
        gui = {
          qt.enable = mkForce false;
          quickshell.enable = mkForce false;
        };
      };
    })
    (mkIf (!config.lib.neg.enabled "mail") {
      features.mail.vdirsyncer.enable = mkForce false;
    })
    # Consistency assertions for nested flags. Only the pairs that are NOT
    # force-disabled above are asserted: when a parent is off, the merge chain
    # already forces the child off (mkForce), so an assertion for those pairs
    # could never fire.
    {
      assertions =
        let
          gui = config.features.gui;
          guiApps = config.features.apps;
        in
        [
          (assertParent gui.enable gui.vicinae.enable
            "features.gui.vicinae.enable requires features.gui.enable = true"
          )
          (assertParent gui.enable guiApps.winapps.enable
            "features.apps.winapps.enable requires features.gui.enable = true"
          )
        ];
    }
  ];
}
