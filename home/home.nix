{
  lib,
  config,
  pkgs,
  systemdUser,
  ...
}: {
  features = {
    # Profile presets (full | lite). Full is default; set to "lite" for headless/minimal.
    profile = lib.mkDefault "full";
    # Temporarily disable Vdirsyncer units/timer until credentials are configured
    mail.vdirsyncer.enable = false;

    # Enable GPG stack (gpg + gpg-agent)
    gpg.enable = true;

    dev = {
      enable = true; # keep dev tooling (editors/toolchains) present on this profile
      ai.enable = true; # ensure AI Studio/LM Studio stays installed for local LLM work
      unreal.enable = true; # Enable Unreal Engine tooling (ue5-sync/build/editor wrappers)
      openxr.enable = true; # Enable OpenXR dev stack (installs Envision UI)
    };

    # Enable AI upscaling features (realtime + offline tools)
    media.aiUpscale = {
      enable = true;
      mode = "realtime"; # toggle live in mpv via Alt+I
      content = "general"; # or "anime"
      scale = 2; # 2 or 4 for realtime path
    };
  };

  imports = [
    ../secrets/home
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

}
