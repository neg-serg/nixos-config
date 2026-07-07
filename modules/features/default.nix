{
  lib,
  config,
  ...
}:
with lib;
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
  ];

  # Apply profile defaults. Users can still override flags after this.
  config = mkMerge [
    # Backward compat: map old `features.profile` (string) to new `features.profiles` (list).
    # The new composable profile system (modules/profiles/) handles actual defaults via mkDefault.
    (mkIf (config.features ? profile && !(config.features ? profiles)) {
      features.profiles = mkDefault (
        if config.features.profile == "lite" then
          [ "lite" ]
        else
          [
            "desktop"
            "dev"
          ]
      );
    })
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
    (mkIf (!config.features.dev.haskell.enable) {
      # When Haskell tooling is disabled, proactively exclude common Haskell tool pnames
      # from curated package lists that honor features.excludePkgs via config.lib.neg.pkgsList.
      features.excludePkgs = mkAfter [
        "ghc"
        "cabal-install"
        "stack"
        "haskell-language-server"
        "hlint"
        "ormolu"
        "fourmolu"
        "hindent"
        "ghcid"
      ];
    })
    (mkIf (!config.features.dev.rust.enable) {
      # When Rust tooling is disabled, exclude common Rust tool pnames
      features.excludePkgs = mkAfter [
        "rustup"
        "rust-analyzer"
        "cargo"
        "rustc"
        "clippy"
        "rustfmt"
      ];
    })
    (mkIf (!config.features.dev.cpp.enable) {
      # When C/C++ tooling is disabled, exclude typical C/C++ tool pnames
      features.excludePkgs = mkAfter [
        "gcc"
        "cmake"
        "ninja"
        "ccache"
        "lldb"
      ];
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
    (mkIf (!config.features.hack.enable) {
      features.hack = { };
    })
    # Consistency assertions for nested flags
    {
      assertions = [
        {
          assertion = config.features.gui.enable || (!config.features.gui.qt.enable);
          message = "features.gui.qt.enable requires features.gui.enable = true";
        }
        {
          assertion = config.features.gui.enable || (!config.features.gui.quickshell.enable);
          message = "features.gui.quickshell.enable requires features.gui.enable = true";
        }
        {
          assertion = config.features.web.enable || (!config.features.web.tools.enable);
          message = "features.web.* flags require features.web.enable = true (disable sub-flags or enable web)";
        }
        {
          assertion = config.features.dev.enable || (!config.features.dev.ai.enable);
          message = "features.dev.ai.enable requires features.dev.enable = true";
        }
        {
          assertion = config.features.dev.ai.enable || (!config.features.dev.ai.opencode.enable);
          message = "features.dev.ai.opencode.enable requires features.dev.ai.enable = true";
        }
        {
          assertion = config.features.dev.ai.enable || (!config.features.dev.ai.openagentscontrol.enable);
          message = "features.dev.ai.openagentscontrol.enable requires features.dev.ai.enable = true";
        }
        {
          assertion = config.features.gui.enable || (!config.features.apps.obsidian.autostart.enable);
          message = "features.apps.obsidian.autostart.enable requires features.gui.enable = true";
        }
        {
          assertion = config.features.gui.enable || (!config.features.apps.winapps.enable);
          message = "features.apps.winapps.enable requires features.gui.enable = true";
        }
        {
          assertion = config.features.gui.enable || (!config.features.apps.guiAppsFull.enable);
          message = "features.apps.guiAppsFull.enable requires features.gui.enable = true";
        }
        {
          assertion = config.features.gui.enable || (!config.features.gui.caelestia-shell.enable);
          message = "features.gui.caelestia-shell.enable requires features.gui.enable = true";
        }
        {
          assertion = config.features.gui.enable || (!config.features.gui.skwd.enable);
          message = "features.gui.skwd.enable requires features.gui.enable = true";
        }
        {
          assertion = config.features.gui.enable || (!config.features.gui.exo.enable);
          message = "features.gui.exo.enable requires features.gui.enable = true";
        }
        {
          assertion = config.features.gui.enable || (!config.features.gui.noctalia.enable);
          message = "features.gui.noctalia.enable requires features.gui.enable = true";
        }
      ];
    }
  ];
}
