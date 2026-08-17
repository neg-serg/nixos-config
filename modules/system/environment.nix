{
  lib,
  pkgs,
  config,
  ...
}:
{
  environment = {
    wordlist.enable = true; # to make "look" utility work
    shells = [ pkgs.zsh ]; # Z shell as allowed system shell
    localBinInPath = true;

    # This is using a rec (recursive) expression to set and access XDG_BIN_HOME within the expression
    # For more on rec expressions see https://nix.dev/tutorials/first-steps/nix-language#recursive-attribute-set-rec
    sessionVariables = {
      # Put setuid wrappers (sudo, newuidmap, pkexec, …) first on PATH:
      # podman/distrobox and sudo break otherwise ("must be owned by uid 0
      # and have the setuid bit set", "newuidmap: Operation not permitted").
      PATH = [ "/run/wrappers/bin" ];
      NIXOS_OZONE_WL = "1"; # Optional, hint Electron apps to use Wayland
      # Force wlroots to use the dGPU (RX 7900 XTX) instead of iGPU
      WLR_DRM_DEVICES = "/dev/dri/by-path/pci-0000:03:00.0-card";
      # Restore Hyprland-specific XDG identifiers for compatibility
      XDG_CURRENT_DESKTOP = "Hyprland";
      XDG_SESSION_DESKTOP = "Hyprland";
      XDG_SESSION_TYPE = "wayland";
      # Prefer Mesa VAAPI on AMD (radeonsi)
      LIBVA_DRIVER_NAME = "radeonsi";
      # Gaming performance (ported from legacy Salt config)
      DXVK_ASYNC = "1";
      DXVK_STATE_CACHE = "1";
      WINE_FULLSCREEN_FSR = "1";
      # HDR support
      DXVK_HDR = if config.lib.neg.enabled "gui.hdr" then "1" else "0";
      mesa_glthread = "true";
      MESA_SHADER_CACHE_MAX_SIZE = "10G";
      STEAM_RUNTIME_PREFER_HOST_LIBRARIES = "1";
      XDG_CACHE_HOME = "$HOME/.cache";
      XDG_CONFIG_HOME = "$HOME/.config";
      XDG_DATA_HOME = "$HOME/.local/share";
      XDG_DESKTOP_DIR = "$HOME/.local/desktop";
      XDG_DOCUMENTS_DIR = "$HOME/doc/";
      XDG_DOWNLOAD_DIR = "$HOME/dw";
      XDG_MUSIC_DIR = "$HOME/music";
      XDG_PICTURES_DIR = "$HOME/pic";
      XDG_PUBLICSHARE_DIR = "$HOME/.local/public";
      XDG_STATE_HOME = "$HOME/.local/state";
      XDG_TEMPLATES_DIR = "$HOME/.local/templates";
      XDG_VIDEOS_DIR = "$HOME/vid";
      ZDOTDIR = "$HOME/.config/zsh";
    };

    extraInit =
      let
        user = config.users.main.name or "neg"; # Load variables from nix-maid
        # Avoid evaluation cycles by not dereferencing users.users.<name>.home here
        homedir = "/home/${user}";
      in
      ''
        if [ "$(id -un)" = "${user}" ]; then
          if [ -f "${homedir}/.local/state/nix/profile/etc/profile.d/session-vars.sh" ]; then
            . "${homedir}/.local/state/nix/profile/etc/profile.d/session-vars.sh"
          fi
        fi
      '';

    variables =
      let
        makePluginPath =
          format:
          (lib.makeSearchPath format [
            "/run/current-system/sw/lib"
            "/etc/profiles/per-user/$USER/lib"
            "$HOME/.local/state/nix/profile/lib"
          ])
          + ":$HOME/.${format}";
        # *_PATH vars for audio plugin formats (NAME_PATH → lowercase dir)
        pluginPaths = lib.genAttrs [
          "CLAP_PATH"
          "DSSI_PATH"
          "LADSPA_PATH"
          "LV2_PATH"
          "LXVST_PATH"
          "VST3_PATH"
          "VST_PATH"
        ] (name: makePluginPath (lib.toLower (lib.removeSuffix "_PATH" name)));
      in
      {
        # Encourage Wayland backends where supported
        QT_QPA_PLATFORM = "wayland;xcb";
        SDL_VIDEODRIVER = "wayland";
        ASPELL_CONF = ''
          per-conf $XDG_CONFIG_HOME/aspell/aspell.conf;
          personal $XDG_CONFIG_HOME/aspell/en_US.pws;
          repl $XDG_CONFIG_HOME/aspell/en.prepl;
        '';
        HISTFILE = "$XDG_DATA_HOME/bash/history";
        INPUTRC = "$XDG_CONFIG_HOME/readline/inputrc";
        LESSHISTFILE = "$XDG_CACHE_HOME/lesshst";
        WGETRC = "$XDG_CONFIG_HOME/wgetrc";
      }
      // pluginPaths;
  };
}
