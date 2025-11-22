{
  lib,
  config,
  ...
}:
with lib; let
  presets = import ./features-data/unfree-presets.nix;
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
      yandex.enable = true;
      prefs.fastfox.enable = true;
    };
    dev = {
      enable = true;
      ai.enable = true;
      rust.enable = true;
      cpp.enable = true;
      haskell.enable = true;
    };
    mail.enable = true;
    hack.enable = true;
    fun.enable = true;
    torrent.enable = true;
    apps = {
      obsidian.autostart.enable = false;
      winapps.enable = false;
    };
  };
  cfg = lib.recursiveUpdate defaults (config.features or {});
  # Use a local mkBool to avoid early dependency on config.lib.neg during option evaluation
  mkBool = desc: default: (lib.mkEnableOption desc) // {inherit default;};
in {
  options.features = {
    # Global package exclusions for curated lists in modules that adopt this filter.
    excludePkgs = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "List of package names (pname) to exclude from curated home.packages lists.";
    };
    profile = mkOption {
      type = types.enum ["full" "lite"];
      default = "full";
      description = "Profile preset that adjusts feature defaults: full or lite.";
    };

    allowUnfree = {
      preset = mkOption {
        type = types.enum (builtins.attrNames presets);
        default = "desktop";
        description = "Preset allowlist for unfree packages.";
      };
      extra = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "Extra unfree package names to allow (in addition to preset).";
      };
      allowed = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "Final allowlist of unfree package names (overrides preset if explicitly set).";
      };
    };

    gui = {
      enable = mkBool "enable GUI stack (wayland/hyprland, quickshell, etc.)" true;
      hy3.enable = mkBool "enable the hy3 tiling plugin for Hyprland" true;
      qt.enable = mkBool "enable Qt integrations for GUI (qt6ct, hyprland-qt-*)" true;
      quickshell.enable = mkBool "enable Quickshell (panel) at login" true;
    };
    mail.enable = mkBool "enable Mail stack (notmuch, isync, vdirsyncer, etc.)" true;
    mail.vdirsyncer.enable = mkBool "enable Vdirsyncer sync service/timer" true;
    cli = {
      fastCnf.enable = mkBool "enable fast zsh command-not-found handler powered by nix-index" true;
      nixIndexDB.enable = mkBool "enable scheduled nix-index DB refresh (prebuilt cache)" true;
      icedteaWeb.enable = mkBool "enable IcedTea Web (netx) integration" false;
    };
    hack.enable = mkBool "enable Hack/security tooling stack" true;
    dev = {
      enable = mkBool "enable Dev stack (toolchains, editors, hack tooling)" true;
      ai = {
        enable = mkBool "enable AI tools (e.g., LM Studio)" true;
      };
      iac = {
        backend = mkOption {
          type = types.enum ["terraform" "tofu"];
          default = "terraform";
          description = "Choose IaC backend: HashiCorp Terraform or OpenTofu (tofu).";
        };
      };
      pkgs = {
        formatters = mkBool "enable CLI/code formatters" true;
        codecount = mkBool "enable code counting tools" true;
        analyzers = mkBool "enable analyzers/linters" true;
        iac = mkBool "enable infrastructure-as-code tooling (Terraform, etc.)" true;
        radicle = mkBool "enable radicle tooling" true;
        runtime = mkBool "enable general dev runtimes (node etc.)" true;
        misc = mkBool "enable misc dev helpers" true;
      };
      hack = {
        core = {
          secrets = mkBool "enable git secret scanners" true;
          reverse = mkBool "enable reverse/disasm helpers" true;
          crawl = mkBool "enable web crawling tools" true;
        };
        forensics = {
          fs = mkBool "enable filesystem/disk forensics tools" true;
          stego = mkBool "enable steganography tools" true;
          analysis = mkBool "enable reverse/binary analysis tools" true;
          network = mkBool "enable network forensics tools" true;
        };
      };
      rust = {
        enable = mkBool "enable Rust tooling (rustup, rust-analyzer)" true;
      };
      cpp = {
        enable = mkBool "enable C/C++ tooling (gcc/clang, cmake, ninja, lldb)" true;
      };
      haskell = {
        enable = mkBool "enable Haskell tooling (ghc, cabal, stack, HLS)" true;
      };
      python = {
        core = mkBool "enable core Python development packages" true;
        tools = mkBool "enable Python tooling (LSP, utilities)" true;
      };
      unreal = {
        enable = mkBool "enable Unreal Engine 5 tooling" false;
        root = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = ''Checkout directory for Unreal Engine sources. Defaults to "~/games/UnrealEngine".'';
          example = "/mnt/storage/UnrealEngine";
        };
        repo = mkOption {
          type = types.str;
          default = "git@github.com:EpicGames/UnrealEngine.git";
          description = "Git URL used by ue5-sync (requires EpicGames/UnrealEngine access).";
        };
        branch = mkOption {
          type = types.str;
          default = "5.4";
          description = "Branch or tag to sync from the Unreal Engine repository.";
        };
        useSteamRun = mkOption {
          type = types.bool;
          default = true;
          description = "Wrap Unreal Editor launch via steam-run to provide FHS runtime libraries.";
        };
      };
      openxr = {
        enable = mkBool "enable OpenXR development stack" false;
        envision.enable = mkBool "install Envision UI for Monado" true;
        runtime = {
          enable = mkBool "install Monado OpenXR runtime" true;
          vulkanLayers.enable = mkBool "install Monado Vulkan layers" true;
          service.enable = mkBool "run monado-service as a user systemd service (graphical preset)" false;
        };
        tools = {
          motoc.enable = mkBool "install motoc (Monado Tracking Origin Calibration)" true;
          basaltMonado.enable = mkBool "install optional basalt-monado tools" false;
        };
      };
    };

    web = {
      enable = mkBool "enable Web stack (browsers + tools)" true;
      default = mkOption {
        type = types.enum ["floorp" "firefox" "librewolf" "nyxt" "yandex"];
        default = "floorp";
        description = "Default browser used for XDG handlers, $BROWSER, and integrations.";
      };
      tools.enable = mkBool "enable web tools (aria2, yt-dlp, misc)" true;
      aria2.service.enable = mkBool "run aria2 download manager as a user service (graphical preset)" false;
      addonsFromNUR.enable = mkBool "install Mozilla addons from NUR packages (heavier eval)" true;
      floorp.enable = mkBool "enable Floorp browser" true;
      firefox.enable = mkBool "enable Firefox browser" false;
      librewolf.enable = mkBool "enable LibreWolf browser" false;
      nyxt.enable = mkBool "enable Nyxt browser" true;
      yandex.enable = mkBool "enable Yandex browser" true;
      prefs = {
        fastfox.enable = mkBool "enable FastFox-like perf prefs for Mozilla browsers" true;
      };
    };

    finance = {
      tws.enable = mkBool "enable Trader Workstation (IBKR) desktop client" false;
    };

    media = {
      aiUpscale = {
        enable = mkBool "enable AI upscaling integration for video (mpv)" false;
        # realtime: use mpv + VapourSynth hook (fast path; requires VS runtime; falls back to no-op if plugin absent)
        # offline: provide a CLI wrapper to render to a new file via Real-ESRGAN
        mode = lib.mkOption {
          type = lib.types.enum ["realtime" "offline"];
          default = "realtime";
          description = "AI upscale mode: realtime (mpv VapourSynth) or offline (CLI pipeline).";
        };
        content = lib.mkOption {
          type = lib.types.enum ["general" "anime"];
          default = "general";
          description = "Tuning/model preference for content type.";
        };
        scale = lib.mkOption {
          type = lib.types.int;
          default = 2;
          description = "Upscale factor for realtime path (2 or 4).";
        };
        installShaders = mkBool "install recommended mpv GLSL shaders (FSRCNNX/SSimSR/Anime4K)" true;
      };
      audio = {
        core.enable = mkBool "enable audio core (PipeWire routing tools)" true;
        apps.enable = mkBool "enable audio apps (players, tools)" true;
        creation.enable = mkBool "enable audio creation stack (DAW, synths)" true;
        mpd.enable = mkBool "enable MPD stack (mpd, clients, mpdris2)" true;
      };
    };

    emulators = {
      retroarch.full = mkBool "use retroarchFull with extended (unfree) cores" false;
    };

    # Torrent stack (Transmission and related tools/services)
    torrent = {
      enable = mkBool "enable Torrent stack (Transmission, tools, services)" true;
    };

    text = {
      read.enable = mkBool "enable reading stack (CLI/GUI viewers, OCR, Recoll)" true;
      manipulate.enable = mkBool "enable text/markup manipulation CLI tools (jq/yq/htmlq)" true;
      notes.enable = mkBool "enable notes tooling (zk CLI)" true;
    };

    # Fun/extras (e.g., curated art assets) that are nice-to-have
    fun = {
      enable = mkBool "enable fun extras (art collections, etc.)" true;
    };

    # GPG stack (gpg, gpg-agent, pinentry)
    gpg.enable = mkBool "enable GPG and gpg-agent (creates ~/.gnupg)" true;

    secrets = {
      enable = mkBool "enable secrets tooling (pass, YubiKey helpers)" true;
    };

    # Development-speed mode: aggressively trim heavy features/inputs for faster local iteration
    devSpeed.enable = mkBool "enable dev-speed mode (trim heavy features for faster eval)" false;

    # General app toggles
    apps = {
      obsidian.autostart.enable =
        mkBool "autostart Obsidian at GUI login (systemd user service)" false;
      winapps.enable =
        mkBool "enable WinApps integration (KVM/libvirt Windows VM, RDP bridge)" false;
    };
  };

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
          yandex.enable = mkDefault false;
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
          yandex.enable = mkDefault true;
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
          yandex.enable = mkDefault false;
          prefs.fastfox.enable = mkDefault false;
        };
        gui.qt.enable = mkDefault false;
        fun.enable = mkDefault false;
        dev.ai.enable = mkDefault false;
        torrent.enable = mkDefault false;
      };
    })
    # If parent feature is disabled, default child toggles to false to avoid contradictions
    (mkIf (! cfg.web.enable) {
      # Parent off must force-disable children to avoid priority conflicts
      features.web = {
        tools.enable = mkForce false;
        addonsFromNUR.enable = mkForce false;
        floorp.enable = mkForce false;
        firefox.enable = mkForce false;
        librewolf.enable = mkForce false;
        nyxt.enable = mkForce false;
        yandex.enable = mkForce false;
        prefs.fastfox.enable = mkForce false;
      };
    })
    # When a parent feature is disabled, force-disable children to avoid priority conflicts
    (mkIf (! cfg.dev.enable) {
      features = {
        dev = {
          ai.enable = mkForce false;
          rust.enable = mkForce false;
          cpp.enable = mkForce false;
        };
      };
    })
    (mkIf (! cfg.dev.haskell.enable) {
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
    (mkIf (! cfg.dev.rust.enable) {
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
    (mkIf (! cfg.dev.cpp.enable) {
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
    (mkIf (! cfg.gui.enable) {
      features = {
        gui = {
          qt.enable = mkForce false;
          # Ensure nested GUI components are disabled when GUI is off
          quickshell.enable = mkForce false;
          hy3.enable = mkForce false;
        };
      };
    })
    (mkIf (! cfg.mail.enable) {
      features.mail.vdirsyncer.enable = mkForce false;
    })
    (mkIf (! cfg.hack.enable) {
      features.hack = {};
    })
    # Consistency assertions for nested flags
    {
      assertions = [
        {
          assertion = cfg.gui.enable || (! cfg.gui.qt.enable);
          message = "features.gui.qt.enable requires features.gui.enable = true";
        }
        {
          assertion = cfg.gui.enable || (! cfg.gui.hy3.enable);
          message = "features.gui.hy3.enable requires features.gui.enable = true";
        }
        {
          assertion = cfg.gui.enable || (! cfg.gui.quickshell.enable);
          message = "features.gui.quickshell.enable requires features.gui.enable = true";
        }
        {
          assertion = cfg.web.enable || (! cfg.web.tools.enable && ! cfg.web.floorp.enable && ! cfg.web.yandex.enable && ! cfg.web.firefox.enable && ! cfg.web.librewolf.enable && ! cfg.web.nyxt.enable);
          message = "features.web.* flags require features.web.enable = true (disable sub-flags or enable web)";
        }
        {
          assertion = ! (cfg.web.firefox.enable && cfg.web.librewolf.enable);
          message = "Only one of features.web.firefox.enable or features.web.librewolf.enable can be true";
        }
        {
          assertion = cfg.dev.enable || (! cfg.dev.ai.enable);
          message = "features.dev.ai.enable requires features.dev.enable = true";
        }
        {
          assertion = cfg.gui.enable || (! cfg.apps.obsidian.autostart.enable);
          message = "features.apps.obsidian.autostart.enable requires features.gui.enable = true";
        }
        {
          assertion = cfg.gui.enable || (! cfg.apps.winapps.enable);
          message = "features.apps.winapps.enable requires features.gui.enable = true";
        }
      ];
    }
  ];
}
