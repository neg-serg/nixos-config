{
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
  imports = [
    ./core.nix
    ./gui.nix
    ./cli.nix
    ./dev.nix
    ./web.nix
    ./media.nix
    ./games.nix
    ./services.nix
    ./apps.nix
    ./misc.nix
    ./hardware.nix
    ./optimization.nix
    ./skwd.nix
    ./system.nix
  ];

  # Apply profile defaults. Users can still override flags after this.
  config = mkMerge [
    # When dev-speed is enabled, prefer lean defaults for heavy subfeatures
    (mkIf config.features.devSpeed.enable {
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
    (mkIf (!config.features.web.enable) {
      # Parent off must force-disable children to avoid priority conflicts
      features.web = {
        tools.enable = mkForce false;
      };
    })
    # When a parent feature is disabled, force-disable children to avoid priority conflicts
    (mkIf (!config.features.dev.enable) {
      features = {
        dev = {
          ai = {
            enable = mkForce false;
            opencode.enable = mkForce false;
            openagentscontrol.enable = mkForce false;
          };
          rust.enable = mkForce false;
          cpp.enable = mkForce false;
        };
      };
    })
    (mkIf (!config.features.dev.haskell.enable || !config.features.dev.rust.enable || !config.features.dev.cpp.enable) {
      # When dev language tooling is disabled, exclude their pnames from curated package lists
      # that honor features.excludePkgs via config.lib.neg.pkgsList.
      features.excludePkgs = mkAfter (
        lib.optionals (!config.features.dev.haskell.enable) [ "ghc" "cabal-install" "stack" "haskell-language-server" "hlint" "ormolu" "fourmolu" "hindent" "ghcid" ]
        ++ lib.optionals (!config.features.dev.rust.enable) [ "rustup" "rust-analyzer" "cargo" "rustc" "clippy" "rustfmt" ]
        ++ lib.optionals (!config.features.dev.cpp.enable) [ "gcc" "cmake" "ninja" "ccache" "lldb" ]
      );
    })
    (mkIf (!config.features.gui.enable) {
      features = {
        gui = {
          qt.enable = mkForce false;
          quickshell.enable = mkForce false;
          exo.enable = mkForce false;
        };
      };
    })
    (mkIf (!config.features.mail.enable) {
      features.mail.vdirsyncer.enable = mkForce false;
    })
    # Consistency assertions for nested flags
    {
      assertions =
        let
          gui = config.features.gui;
          dev = config.features.dev;
          devAi = dev.ai;
          guiApps = config.features.apps;
        in
        [
          (assertParent gui.enable gui.qt.enable "features.gui.qt.enable requires features.gui.enable = true")
          (assertParent gui.enable gui.quickshell.enable "features.gui.quickshell.enable requires features.gui.enable = true")
          (assertParent gui.enable gui.caelestia-shell.enable "features.gui.caelestia-shell.enable requires features.gui.enable = true")
          (assertParent gui.enable gui.skwd.enable "features.gui.skwd.enable requires features.gui.enable = true")
          (assertParent gui.enable gui.exo.enable "features.gui.exo.enable requires features.gui.enable = true")
          (assertParent gui.enable gui.noctalia.enable "features.gui.noctalia.enable requires features.gui.enable = true")
          (assertParent gui.enable gui.vicinae.enable "features.gui.vicinae.enable requires features.gui.enable = true")
          (assertParent gui.enable guiApps.obsidian.autostart.enable "features.apps.obsidian.autostart.enable requires features.gui.enable = true")
          (assertParent gui.enable guiApps.winapps.enable "features.apps.winapps.enable requires features.gui.enable = true")
          (assertParent gui.enable guiApps.guiAppsFull.enable "features.apps.guiAppsFull.enable requires features.gui.enable = true")
          (assertParent config.features.web.enable config.features.web.tools.enable "features.web.* flags require features.web.enable = true (disable sub-flags or enable web)")
          (assertParent dev.enable devAi.enable "features.dev.ai.enable requires features.dev.enable = true")
          (assertParent devAi.enable devAi.opencode.enable "features.dev.ai.opencode.enable requires features.dev.ai.enable = true")
          (assertParent devAi.enable devAi.openagentscontrol.enable "features.dev.ai.openagentscontrol.enable requires features.dev.ai.enable = true")
        ];
    }
  ];
}
