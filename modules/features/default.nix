{
  lib,
  config,
  ...
}:
with lib;
let
  defaults = {
    profile = "full";
    devSpeed.enable = false;
    gui = {
      enable = true;
      hy3.enable = true;
      qt.enable = true;
      quickshell.enable = true;
    };
    web = {
      enable = true;
      tools.enable = true;
      addonsFromNUR.enable = true;
      floorp.enable = true;
      firefox.enable = false;
      librewolf.enable = false;
      nyxt.enable = true;

      prefs.fastfox.enable = true;
    };
    dev = {
      enable = true;
      ai = {
        enable = true;
        antigravity.enable = false;
      };
      rust.enable = true;
      cpp.enable = true;
      haskell.enable = true;
    };
    mail.enable = true;
    hack.enable = true;
    fun.enable = true;
    torrent = {
      enable = true;
      prometheus.enable = false;
    };
    net = {
      wifi.enable = false;
    };
    apps = {
      obsidian.autostart.enable = false;
      winapps.enable = false;
    };
  };
  cfg = lib.recursiveUpdate defaults (config.features or { });
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
  ];

  # Apply profile defaults. Users can still override flags after this.
  config = mkMerge [
    (mkIf (cfg.profile == "lite") {
      # Slim defaults for lite profile
      features = {
        torrent.enable = mkDefault false;
        gui.enable = mkDefault false;
        mail.enable = mkDefault false;
        hack.enable = mkDefault false;
        dev = {
          enable = mkDefault false;
          ai.enable = mkDefault false;
        };
        # Explicitly disable Unreal tooling in lite to avoid asserts
        dev.unreal.enable = mkForce false;
        media.audio = {
          core.enable = mkDefault false;
          apps.enable = mkDefault false;
          creation.enable = mkDefault false;
          mpd.enable = mkDefault false;
        };
        web = {
          enable = mkDefault false;
          tools.enable = mkDefault false;
          addonsFromNUR.enable = mkDefault false;
          floorp.enable = mkDefault false;

          prefs.fastfox.enable = mkDefault false;
        };
        emulators.retroarch.full = mkDefault false;
        fun.enable = mkDefault false;
      };
    })
    (mkIf (cfg.profile == "full") {
      # Rich defaults for full profile
      features = {
        torrent.enable = mkDefault true;
        web = {
          enable = mkDefault true;
          tools.enable = mkDefault true;
          addonsFromNUR.enable = mkDefault true;
          floorp.enable = mkDefault true;
          firefox.enable = mkDefault false;
          librewolf.enable = mkDefault false;
          nyxt.enable = mkDefault true;

          prefs.fastfox.enable = mkDefault true;
        };
        media.audio = {
          core.enable = mkDefault true;
          apps.enable = mkDefault true;
          creation.enable = mkDefault true;
          mpd.enable = mkDefault true;
        };
        emulators.retroarch.full = mkDefault true;
        fun.enable = mkDefault true;
        dev.ai.enable = mkDefault true;
      };
    })
    # When dev-speed is enabled, prefer lean defaults for heavy subfeatures
    (mkIf cfg.devSpeed.enable {
      features = {
        web = {
          tools.enable = mkDefault false;
          addonsFromNUR.enable = mkDefault false;
          floorp.enable = mkDefault false;
          firefox.enable = mkDefault false;
          librewolf.enable = mkDefault false;
          nyxt.enable = mkDefault false;

          prefs.fastfox.enable = mkDefault false;
        };
        gui.qt.enable = mkDefault false;
        fun.enable = mkDefault false;
        dev.ai.enable = mkDefault false;
        torrent.enable = mkDefault false;
      };
    })
    # If parent feature is disabled, default child toggles to false to avoid contradictions
    (mkIf (!cfg.web.enable) {
      # Parent off must force-disable children to avoid priority conflicts
      features.web = {
        tools.enable = mkForce false;
        addonsFromNUR.enable = mkForce false;
        floorp.enable = mkForce false;
        firefox.enable = mkForce false;
        librewolf.enable = mkForce false;
        nyxt.enable = mkForce false;

        prefs.fastfox.enable = mkForce false;
      };
    })
    # When a parent feature is disabled, force-disable children to avoid priority conflicts
    (mkIf (!cfg.dev.enable) {
      features = {
        dev = {
          ai.enable = mkForce false;
          rust.enable = mkForce false;
          cpp.enable = mkForce false;
        };
      };
    })
    (mkIf (!cfg.dev.haskell.enable) {
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
    (mkIf (!cfg.dev.rust.enable) {
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
    (mkIf (!cfg.dev.cpp.enable) {
      # When C/C++ tooling is disabled, exclude typical C/C++ tool pnames
      features.excludePkgs = mkAfter [
        "gcc"
        "clang"
        "clang-tools"
        "cmake"
        "ninja"
        "bear"
        "ccache"
        "lldb"
      ];
    })
    (mkIf (!cfg.gui.enable) {
      features = {
        gui = {
          qt.enable = mkForce false;
          # Ensure nested GUI components are disabled when GUI is off
          quickshell.enable = mkForce false;
          hy3.enable = mkForce false;
          walker.enable = mkForce false;
        };
      };
    })
    (mkIf (!cfg.mail.enable) {
      features.mail.vdirsyncer.enable = mkForce false;
    })
    (mkIf (!cfg.hack.enable) {
      features.hack = { };
    })
    # Consistency assertions for nested flags
    {
      assertions = [
        {
          assertion = cfg.gui.enable || (!cfg.gui.qt.enable);
          message = "features.gui.qt.enable requires features.gui.enable = true";
        }
        {
          assertion = cfg.gui.enable || (!cfg.gui.hy3.enable);
          message = "features.gui.hy3.enable requires features.gui.enable = true";
        }
        {
          assertion = cfg.gui.enable || (!cfg.gui.quickshell.enable);
          message = "features.gui.quickshell.enable requires features.gui.enable = true";
        }
        {
          assertion = cfg.gui.enable || (!cfg.gui.walker.enable);
          message = "features.gui.walker.enable requires features.gui.enable = true";
        }
        {
          assertion =
            cfg.web.enable
            || (
              !cfg.web.tools.enable
              && !cfg.web.floorp.enable

              && !cfg.web.firefox.enable
              && !cfg.web.librewolf.enable
              && !cfg.web.nyxt.enable
            );
          message = "features.web.* flags require features.web.enable = true (disable sub-flags or enable web)";
        }
        {
          assertion = !(cfg.web.firefox.enable && cfg.web.librewolf.enable);
          message = "Only one of features.web.firefox.enable or features.web.librewolf.enable can be true";
        }
        {
          assertion = cfg.dev.enable || (!cfg.dev.ai.enable);
          message = "features.dev.ai.enable requires features.dev.enable = true";
        }
        {
          assertion = cfg.dev.ai.enable || (!cfg.dev.ai.antigravity.enable);
          message = "features.dev.ai.antigravity.enable requires features.dev.ai.enable = true";
        }
        {
          assertion = cfg.gui.enable || (!cfg.apps.obsidian.autostart.enable);
          message = "features.apps.obsidian.autostart.enable requires features.gui.enable = true";
        }
        {
          assertion = cfg.gui.enable || (!cfg.apps.winapps.enable);
          message = "features.apps.winapps.enable requires features.gui.enable = true";
        }
      ];
    }
  ];
}
