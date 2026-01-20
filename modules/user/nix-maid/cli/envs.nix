{
  config,
  lib,
  pkgs,
  ...
}:
let
  homeDir = config.users.users.neg.home;
  dataHome = "${homeDir}/.local/share";
  configHome = "${homeDir}/.config";
  cacheHome = "${homeDir}/.cache";
in
{
  environment.variables = {
    # NixOS handles standard XDG variables by default if xdg.enable is true,
    # but we force them here to match standard profile config
    XDG_CACHE_HOME = lib.mkForce cacheHome;
    XDG_CONFIG_HOME = lib.mkForce configHome;
    XDG_DATA_HOME = lib.mkForce dataHome;
    XDG_DESKTOP_DIR = lib.mkForce "${homeDir}/.local/desktop";
    XDG_DOCUMENTS_DIR = lib.mkForce "${homeDir}/doc";
    XDG_DOWNLOAD_DIR = lib.mkForce "${homeDir}/dw";
    XDG_MUSIC_DIR = lib.mkForce "${homeDir}/music";
    XDG_PICTURES_DIR = lib.mkForce "${homeDir}/pic";
    XDG_PUBLICSHARE_DIR = lib.mkForce "${homeDir}/.local/public";
    XDG_STATE_HOME = lib.mkForce "${homeDir}/.local/state";
    XDG_TEMPLATES_DIR = lib.mkForce "${homeDir}/.local/templates";
    XDG_VIDEOS_DIR = lib.mkForce "${homeDir}/vid";
    # XDG_RUNTIME_DIR is managed by systemd-logind

    # Custom Env Vars (Global / Miscellaneous)
    CRAWL_DIR = "${dataHome}/crawl/";
    __GL_VRR_ALLOWED = "1";
    GRIM_DEFAULT_DIR = "${homeDir}/pic/shots";
    LIBSEAT_BACKEND = "logind";
    PASSWORD_STORE_DIR = "${dataHome}/pass";
    PASSWORD_STORE_ENABLE_EXTENSIONS_DEFAULT = "true";
    PYTHON_HISTORY = "${dataHome}/python/history";
    PULSE_COOKIE = "${configHome}/pulse/cookie";
    TERMINFO = "${dataHome}/terminfo";
    TERMINFO_DIRS = "${dataHome}/terminfo:/usr/share/terminfo";
    WINEPREFIX = "${dataHome}/wineprefixes/default";
    XAUTHORITY = "$XDG_RUNTIME_DIR/Xauthority";
    XINITRC = "${configHome}/xinit/xinitrc";
    XSERVERRC = "${configHome}/xinit/xserverrc";
    XZ_DEFAULTS = "-T 0";
    ZDOTDIR = lib.mkForce "${configHome}/zsh";

    # XDG compliance (xdg-ninja fixes)
    ANDROID_USER_HOME = "${dataHome}/android";

    GNUPGHOME = "${dataHome}/gnupg";
    GTK2_RC_FILES = "${configHome}/gtk-2.0/gtkrc";
    NPM_CONFIG_CACHE = "${cacheHome}/npm";
    NPM_CONFIG_INIT_MODULE = "${configHome}/npm/config/npm-init.js";
    NPM_CONFIG_TMP = "$XDG_RUNTIME_DIR/npm";
  };

  # Activation script to ensure profile links (legacy support)
  system.activationScripts.negProfileLinks = lib.stringAfter [ "users" ] ''
    echo "Ensuring legacy profile links for user neg..."
    ${pkgs.util-linux}/bin/runuser -u neg -- ${pkgs.bash}/bin/bash -c ' # Set of system utilities for Linux
      set -eu
      mkdir -p "$HOME/.local/state/nix/profiles"
      PROFILE_TARGET="/etc/profiles/per-user/neg"

      ln -sfn "$PROFILE_TARGET" "$HOME/.local/state/nix/profiles/profile"
      ln -sfn "$HOME/.local/state/nix/profiles/profile" "$HOME/.local/state/nix/profile"
      ln -sfn "$HOME/.local/state/nix/profiles/profile" "$HOME/.nix-profile"

      # Legacy zshenv-extra logic: ensure ~/tmp is a symlink to a temp dir if invalid
      # (Though usually ~/tmp should be ephemeral or just a dir)
      # We replicate the logic from home/modules/user/envs/zshenv-extra.sh
      if [ ! -e "$HOME/tmp" ] || [ ! -L "$HOME/tmp" ]; then
         rm -rf "$HOME/tmp"
         # Create a secure temp dir and link it?
         # The original script does `tmp_loc=$(mktemp -d); ln -fs ...`
         # But mktemp -d creates it in /tmp usually.
         # Ideally we just want ~/tmp to exist.
         mkdir -p "$HOME/tmp"
      fi

    '
  '';
}
