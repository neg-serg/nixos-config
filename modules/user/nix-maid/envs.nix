{
  config,
  lib,
  pkgs,
  ...
}: let
  homeDir = config.users.users.neg.home;
  dataHome = "${homeDir}/.local/share";
  configHome = "${homeDir}/.config";
in {
  environment.variables = {
    # Custom Env Vars (Global / Miscellaneous)
    CRAWL_DIR = "${dataHome}/crawl/";
    __GL_VRR_ALLOWED = "1";
    GRIM_DEFAULT_DIR = "${homeDir}/pic/shots";
    LIBSEAT_BACKEND = "logind";
    PASSWORD_STORE_DIR = "${dataHome}/pass";
    PASSWORD_STORE_ENABLE_EXTENSIONS_DEFAULT = "true";
    TERMINFO = "${dataHome}/terminfo";
    TERMINFO_DIRS = "${dataHome}/terminfo:/usr/share/terminfo";
    WINEPREFIX = "${dataHome}/wineprefixes/default";
    XAUTHORITY = "$XDG_RUNTIME_DIR/Xauthority";
    XINITRC = "${configHome}/xinit/xinitrc";
    XSERVERRC = "${configHome}/xinit/xserverrc";
    XZ_DEFAULTS = "-T 0";
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
