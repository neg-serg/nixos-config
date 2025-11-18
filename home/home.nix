{
  lib,
  config,
  pkgs,
  caches,
  systemdUser,
  ...
}: let
  # Reuse flake-provided caches passed via mkHMArgs (single source of truth)
  cachixSubstituters = caches.substituters or [];
  cachixTrustedKeys = caches.trustedPublicKeys or [];
in {
  features = {
    # Profile presets (full | lite). Full is default; set to "lite" for headless/minimal.
    profile = lib.mkDefault "full";
    # Exclude problematic packages from curated lists without editing modules
    excludePkgs = [
      # Network sniffing/passwords
      "dsniff"
      "crowbar"
      # Backdoor/tunneling tool candidates kept off by default
      "dns2tcp"
      "exe2hexbat"
      "laudanum"
      "mimikatz"
      "nishang"
      "powersploit"
      "ptunnel"
      "sbd"
      "shellter"
      "stunnel4"
      "veil"
      "webacoo"
      "weevely"
      # OpenMW now uses upstream packaging; not excluded
    ];

    # Temporarily disable Vdirsyncer units/timer until credentials are configured
    mail.vdirsyncer.enable = false;

    # Enable GPG stack (gpg + gpg-agent)
    gpg.enable = true;

    gui = {
      # Enable hy3 plugin/config for Hyprland
      hy3.enable = true;
      # Enable hyprsplit layout plugin for Hyprland
      hyprsplit.enable = true;
      # Enable hyprland-vrr plugin
      vrr.enable = true;
    };

    dev = {
      # Enable Unreal Engine tooling (ue5-sync/build/editor wrappers)
      unreal.enable = true;

      # Enable OpenXR dev stack (installs Envision UI)
      openxr.enable = true;

    };

    # Enable AI upscaling features (realtime + offline tools)
    media.aiUpscale = {
      enable = true;
      mode = "realtime"; # toggle live in mpv via Alt+I
      content = "general"; # or "anime"
      scale = 2; # 2 or 4 for realtime path
    };
  };

  # Prewarm removed: persistent launcher services are disabled

  # XDG aggregated fixups were removed; rely on per‑file `force = true` when needed.

  # Unfree policy centralized in modules/misc/unfree.nix (features.allowUnfree.allowed)

  nix = {
    package = lib.mkDefault pkgs.nix;
    # Per-user Nix settings
    settings = {
      # Trust flake-provided nixConfig (substituters, keys, features)
      accept-flake-config = true;
      # Use XDG paths so Home Manager uses modern v2 profile (nix profile)
      use-xdg-base-directories = true;
      # Speed + safety: keep eval cache on and forbid IFD during eval
      eval-cache = true;
      allow-import-from-derivation = false;
      # Use the sops-managed GitHub netrc for authenticated fetches
      netrc-file = config.sops.secrets."github-netrc".path;
      # Ensure features are available; caches and keys come from flake nixConfig (via mkHMArgs)
      experimental-features = ["nix-command" "flakes"];
      # Make caches visible in `nix show-config` via flake-provided lists
      # Keep cache.nixos.org first to retain the official cache
      substituters = ["https://cache.nixos.org/"] ++ cachixSubstituters;
      trusted-public-keys =
        ["cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="]
        ++ cachixTrustedKeys;
    };
  };
  imports = [
    ./secrets
    ./modules
  ];
  # Local AI (Ollama) as a user service
  systemd.user.services."local-ai" = lib.mkMerge [
    {
      Unit = {Description = "Local AI (Ollama)";};
      Service = {
        ExecStart = "${pkgs.ollama}/bin/ollama serve";
        Environment = [
          # For LocalAI compatibility (unused by Ollama shim)
          "MODELS_PATH=${config.xdg.dataHome}/localai/models"
          # Effective for Ollama
          "OLLAMA_MODELS=${config.xdg.dataHome}/ollama"
          "OLLAMA_HOST=127.0.0.1:11434"
        ];
        Restart = "on-failure";
        RestartSec = "2s";
      };
    }
    (systemdUser.mkUnitFromPresets {presets = ["defaultWanted"];})
  ];
  xdg.stateHome = "${config.home.homeDirectory}/.local/state";
  home = {
    homeDirectory = "/home/neg";
    stateVersion = "23.11"; # Please read the comment before changing.
    preferXdgDirectories = true;
    username = "neg";
  };

  # Auto-push built store paths to Cachix
  services.cachix.watchStore = {
    enable = false;
    cacheName = "neg-serg";
    authTokenFile = config.sops.secrets."cachix_env".path;
  };
}
