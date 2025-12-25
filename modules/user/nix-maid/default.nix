{
  inputs,
  pkgs,
  lib,
  ...
}: {
  imports = [
    inputs.nix-maid.nixosModules.default # user configuration framework (nix-maid)
    ./git.nix
    ./mpv.nix
    ./shells.nix
    ./user-services.nix
    ./secrets.nix
    ./theme.nix
    ./xdg.nix
    ./dunst.nix
    ./services-manual.nix
    ./gpg.nix
    ./cli
    ./broot.nix
    ./tig.nix
    ./tewi.nix
    ./gui-apps.nix
    ./vicinae.nix
    ./walker.nix
    ./quickshell.nix
    ./qt.nix
    ./firefox.nix
    ./floorp.nix
    ./yazi.nix
    ./pipewire.nix
    ./emacs.nix
    ./transmission.nix
    ./vdirsyncer.nix
    ./khal.nix
    ./dosemu.nix
    ./enchant.nix
    ./nethack.nix
    ./television.nix
    ./hyprland.nix
    ./media.nix
    ./mail.nix
    ./autoclick.nix
    ./asciinema.nix
    ./fun-launchers.nix
    ./nekoray.nix
    ./nyxt.nix
    ./tridactyl.nix
    ./steam.nix
    ./local-bin.nix
    ./oss-games.nix
    ./envs.nix
    ./web/librewolf.nix
    ./web/aria.nix
    ./web/misc.nix
    ./web/yt-dlp.nix
    ./web/defaults.nix
    ./web/browsing.nix
    ./dev.nix
    ./misc.nix
    ./text.nix
    ./distros.nix
    ./flatpak.nix
  ];

  users.users.neg.maid = {};

  # Activation script to force restart maid-activation for 'neg'.
  # This ensures user configs are reapplied on every switch, working around
  # NixOS's behavior of not automatically restarting user services reliably.
  system.activationScripts.maidForceRestart = lib.stringAfter ["users"] ''
    if [ -e /run/user/1000 ]; then
      echo "Restarting maid-activation for user 1000..."

      # Cleanup stale symlinks that conflict with new nix-maid management
      # These directories were previously linked via linkImpure or similar mechanisms
      ${pkgs.util-linux}/bin/runuser -u neg -- ${pkgs.bash}/bin/bash -c '
        for dir in "$HOME/.config/rmpc" "$HOME/.config/swayimg" "$HOME/.config/vicinae"; do
          if [ -L "$dir" ]; then
            echo "Removing stale symlink: $dir"
            rm "$dir"
            mkdir -p "$dir"
          fi
        done
      '

      ${pkgs.util-linux}/bin/runuser -u neg -- ${pkgs.bash}/bin/bash -c "XDG_RUNTIME_DIR=/run/user/1000 ${pkgs.systemd}/bin/systemctl --user restart maid-activation.service" || true
    fi
  '';
}
