{
  inputs,
  pkgs,
  lib,
  ...
}:
{
  imports = [
    inputs.nix-maid.nixosModules.default # user configuration framework (nix-maid)
    # ../../core/home-manager-lite.nix # Native replacement (fast eval)

    # Core & GUI
    ./gui/theme.nix
    ./gui/xdg.nix
    ./gui/qt.nix
    ./gui/dunst.nix
    ./gui/walker.nix
    ./gui/quickshell.nix
    ./hyprland/main.nix

    # Applications (GUI/TUI)
    ./apps/mpv
    ./apps/gui-apps.nix
    ./apps/vicinae.nix
    ./apps/emacs.nix
    ./apps/transmission.nix

    # CLI & Shell Environment
    ./cli
    ./cli/git.nix
    ./cli/shells.nix
    ./cli/broot.nix
    ./cli/tig.nix
    ./cli/tewi.nix
    # ./cli/yazi.nix is imported via ./cli
    ./cli/television.nix
    ./cli/envs.nix
    ./cli/emulators.nix
    ./cli/asciinema.nix
    ./cli/local-bin.nix

    # System & Services
    ./sys/secrets.nix
    ./sys/user-services.nix
    ./sys/services-manual.nix
    ./sys/gpg.nix
    ./sys/enchant.nix
    ./sys/distros.nix
    ./sys/flatpak.nix
    ./sys/dev.nix
    ./sys/vdirsyncer.nix
    ./sys/khal.nix
    ./sys/autoclick.nix
    ./sys/nekoray.nix
    ./sys/mail.nix
    ./sys/misc.nix

    # Web & Browsing
    ./web/browsing.nix # includes defaults.nix, librewolf.nix
    ./web/firefox.nix
    ./web/floorp.nix
    # ./web/librewolf.nix is imported via ./web/browsing.nix
    ./web/brave.nix
    ./web/vivaldi.nix
    ./web/edge.nix

    ./web/aria.nix
    ./web/misc.nix
    ./web/yt-dlp.nix
    # ./web/tridactyl.nix # disabled in favor of surfingkeys

    # Fun & Games
    ./fun/nethack.nix
    ./fun/oss-games.nix
    ./fun/openmw.nix
    ./fun/steam.nix

    # Media & Audio
    ./sys/media.nix
    ./sys/pipewire.nix
  ];

  users.users.neg.maid = { };

  # Activation script to force restart maid-activation for 'neg'.
  # This ensures user configs are reapplied on every switch, working around
  # NixOS's behavior of not automatically restarting user services reliably.
  system.activationScripts.maidForceRestart = lib.stringAfter [ "users" ] ''
    if [ -e /run/user/1000 ]; then
      echo "Restarting maid-activation for user 1000..."

      # Cleanup stale symlinks that conflict with new nix-maid management
      # These directories were previously linked via linkImpure or similar mechanisms
      ${pkgs.util-linux}/bin/runuser -u neg -- ${pkgs.bash}/bin/bash -c ' # Set of system utilities for Linux
        for dir in "$HOME/.config/rmpc" "$HOME/.config/swayimg" "$HOME/.config/vicinae"; do
          if [ -L "$dir" ]; then
            echo "Removing stale symlink: $dir"
            rm "$dir"
            mkdir -p "$dir"
          fi
        done
      '

      # Async restart: run in background to not block deploy, use --no-block to avoid waiting, and silence output
      (${pkgs.util-linux}/bin/runuser -u neg -- ${pkgs.bash}/bin/bash -c "XDG_RUNTIME_DIR=/run/user/1000 ${pkgs.systemd}/bin/systemctl --user restart --no-block maid-activation.service" >/dev/null 2>&1 &) || true # System and service manager for Linux | Set of system utilities for Linux
    fi
  '';
}
