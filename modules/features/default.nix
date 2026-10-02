{
  neg,
  lib,
  config,
  ...
}:
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
  config = lib.mkMerge [
    # When dev-speed is enabled, prefer lean defaults for heavy subfeatures
    (lib.mkIf (config.lib.neg.enabled "devSpeed") {
      features = {
        web = {
          tools.enable = lib.mkDefault false;
        };
        gui.qt.enable = lib.mkDefault false;
        fun.enable = lib.mkDefault false;
        dev.ai.enable = lib.mkDefault false;
        torrent.enable = lib.mkDefault false;
      };
    })
    # If parent feature is disabled, default child toggles to false to avoid contradictions
    (lib.mkIf (!config.lib.neg.enabled "web") {
      # Parent off must force-disable children to avoid priority conflicts
      features.web = {
        tools.enable = lib.mkForce false;
      };
    })
    # When a parent feature is disabled, force-disable children to avoid priority conflicts
    (lib.mkIf (!config.lib.neg.enabled "dev") {
      features = {
        dev = {
          ai = {
            enable = lib.mkForce false;
          };
          rust.enable = lib.mkForce false;
          cpp.enable = lib.mkForce false;
        };
      };
    })
    (lib.mkIf (!config.lib.neg.enabled "gui") {
      features = {
        gui = {
          qt.enable = lib.mkForce false;
          quickshell.enable = lib.mkForce false;
        };
      };
    })
    (lib.mkIf (!config.lib.neg.enabled "mail") {
      features.mail.vdirsyncer.enable = lib.mkForce false;
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
