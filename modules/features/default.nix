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
  imports =
    builtins.readDir ./.
    |> builtins.attrNames
    |> builtins.filter (n: n != "default.nix" && lib.hasSuffix ".nix" n)
    |> builtins.map (n: ./. + "/${n}");

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
    (mkIf
      (
        !config.lib.neg.enabled "dev.haskell"
        || !config.lib.neg.enabled "dev.rust"
        || !config.lib.neg.enabled "dev.cpp"
        || !config.lib.neg.enabled "dev.java"
      )
      {
        # When dev language tooling is disabled, exclude their pnames from curated package lists
        # that honor features.excludePkgs via config.lib.neg.pkgsList.
        features.excludePkgs = mkAfter (
          lib.optionals (!config.lib.neg.enabled "dev.haskell") [
            "ghc"
            "cabal-install"
            "stack"
            "haskell-language-server"
            "hlint"
            "ormolu"
            "fourmolu"
            "hindent"
            "ghcid"
          ]
          ++ lib.optionals (!config.lib.neg.enabled "dev.rust") [
            "rustup"
            "rust-analyzer"
            "cargo"
            "rustc"
            "clippy"
            "rustfmt"
          ]
          ++ lib.optionals (!config.lib.neg.enabled "dev.cpp") [
            "gcc"
            "cmake"
            "ninja"
            "ccache"
            "lldb"
          ]
          ++ lib.optionals (!config.lib.neg.enabled "dev.java") [
            "jdk"
            "maven"
          ]
        );
      }
    )
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
          (assertParent gui.enable gui.quickshell.enable
            "features.gui.quickshell.enable requires features.gui.enable = true"
          )
          (assertParent gui.enable gui.vicinae.enable
            "features.gui.vicinae.enable requires features.gui.enable = true"
          )
          (assertParent gui.enable guiApps.winapps.enable
            "features.apps.winapps.enable requires features.gui.enable = true"
          )
          (assertParent (config.lib.neg.enabled "web") (config.lib.neg.enabled "web.tools")
            "features.web.* flags require features.web.enable = true (disable sub-flags or enable web)"
          )
          (assertParent dev.enable devAi.enable "features.dev.ai.enable requires features.dev.enable = true")
        ];
    }
  ];
}
