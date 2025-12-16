{
  config,
  lib,
  pkgs,
  ...
}: let
  homeDir = config.users.users.neg.home;
  dataHome = "${homeDir}/.local/share";
  configHome = "${homeDir}/.config";
  cacheHome = "${homeDir}/.cache";
in {
  environment.variables = {
    # NixOS handles standard XDG variables by default if xdg.enable is true,
    # but we force them here to match the legacy Home Manager config
    XDG_CACHE_HOME = cacheHome;
    XDG_CONFIG_HOME = configHome;
    XDG_DATA_HOME = dataHome;
    XDG_DESKTOP_DIR = "${homeDir}/.local/desktop";
    XDG_DOCUMENTS_DIR = "${homeDir}/doc";
    XDG_DOWNLOAD_DIR = "${homeDir}/dw";
    XDG_MUSIC_DIR = "${homeDir}/music";
    XDG_PICTURES_DIR = "${homeDir}/pic";
    XDG_PUBLICSHARE_DIR = "${homeDir}/.local/public";
    XDG_STATE_HOME = "${homeDir}/.local/state";
    XDG_TEMPLATES_DIR = "${homeDir}/.local/templates";
    XDG_VIDEOS_DIR = "${homeDir}/vid";
    # XDG_RUNTIME_DIR is managed by systemd-logind

    # Custom Env Vars
    CARGO_HOME = "${dataHome}/cargo";
    ENCHANT_CONFIG_DIR = "${configHome}/enchant";
    RUSTUP_HOME = "${dataHome}/rustup";
    CCACHE_CONFIGPATH = "${configHome}/ccache.config";
    CCACHE_DIR = "${cacheHome}/ccache";
    CRAWL_DIR = "${dataHome}/crawl/";
    EZA_COLORS = "da=03:uu=01:gu=0:ur=0:uw=03:ux=04;38;5;24:gr=0:gx=01;38;5;24:tx=01;38;5;24;ur=00;ue=00:tr=00:tw=00:tx=00";
    GHCUP_USE_XDG_DIRS = "1";
    __GL_VRR_ALLOWED = "1";
    GREP_COLOR = "37;45";
    GREP_COLORS = "ms=0;32:mc=1;33:sl=:cx=:fn=1;32:ln=1;36:bn=36:se=1;30";
    GRIM_DEFAULT_DIR = "${homeDir}/pic/shots";
    HTTPIE_CONFIG_DIR = "${configHome}/httpie";
    INPUTRC = "${configHome}/inputrc";
    _JAVA_OPTIONS = "-Djava.util.prefs.userRoot=${configHome}/java";
    LIBSEAT_BACKEND = "logind";
    MPV_HOME = "${configHome}/mpv";
    PARALLEL_HOME = "${configHome}/parallel";
    PASSWORD_STORE_DIR = "${dataHome}/pass";
    PASSWORD_STORE_ENABLE_EXTENSIONS_DEFAULT = "true";
    # DISPLAY is set by graphical session
    MANWIDTH = "80";
    NOTMUCH_CONFIG = "${configHome}/notmuch/notmuchrc";
    PIPEWIRE_DEBUG = "0";
    PIPEWIRE_LOG_SYSTEMD = "true";
    PYLINTHOME = "${configHome}/pylint";
    QMK_HOME = "${homeDir}/src/qmk_firmware";
    TERMINAL = "kitty";
    TERMINFO = "${dataHome}/terminfo";
    TERMINFO_DIRS = "${dataHome}/terminfo:/usr/share/terminfo";
    VAGRANT_HOME = "${dataHome}/vagrant";
    CUDA_CACHE_PATH = "${cacheHome}/cuda";
    LLVM_PROFILE_FILE = "${cacheHome}/llvm/%h-%p-%m.profraw";
    GOMODCACHE = "${cacheHome}/gomod";
    WINEPREFIX = "${dataHome}/wineprefixes/default";
    WORDCHARS = "*?_-.[]~&;!#$%^(){}<>~\\` ";
    XAUTHORITY = "$XDG_RUNTIME_DIR/Xauthority";
    XINITRC = "${configHome}/xinit/xinitrc";
    XSERVERRC = "${configHome}/xinit/xserverrc";
    XZ_DEFAULTS = "-T 0";
    ZDOTDIR = "${configHome}/zsh";
  };

  # Activation script to ensure profile links (legacy support)
  system.activationScripts.negProfileLinks = lib.stringAfter ["users"] ''
    echo "Ensuring legacy profile links for user neg..."
    ${pkgs.util-linux}/bin/runuser -u neg -- ${pkgs.bash}/bin/bash -c '
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
