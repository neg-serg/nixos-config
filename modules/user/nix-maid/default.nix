{
  inputs,
  pkgs,
  lib,
  ...
}: {
  imports = [
    # inputs.nix-maid.nixosModules.default # user configuration framework (nix-maid)
    ../../core/home-manager-lite.nix # Native replacement (fast eval)

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
    ./apps/nyxt.nix
    ./apps/emacs.nix
    ./apps/editors.nix
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
    ./sys/text.nix
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
    ./web/chrome.nix
    ./web/brave.nix
    ./web/vivaldi.nix
    ./web/edge.nix
    ./web/yandex.nix
    ./web/aria.nix
    ./web/misc.nix
    ./web/yt-dlp.nix
    # ./web/tridactyl.nix # disabled in favor of surfingkeys

    # Fun & Games
    ./fun/nethack.nix
    ./fun/fun-launchers.nix
    ./fun/oss-games.nix
    ./fun/steam.nix

    # Media & Audio
    ./sys/media.nix
    ./sys/pipewire.nix
  ];

  # users.users.neg.maid = {};

  # Activation script to force restart maid-activation for 'neg'.
  # This ensures user configs are reapplied on every switch, working around
  # NixOS's behavior of not automatically restarting user services reliably.
  # system.activationScripts.maidForceRestart removed (native activation handles this)
}
