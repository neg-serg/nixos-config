{inputs, ...}: {
  imports = [
    inputs.nix-maid.nixosModules.default
    ./git.nix
    ./mpv.nix
    ./shell.nix
    ./dunst.nix
    ./dunst.nix
    ./mpd-services.nix
    ./services-manual.nix
    ./gpg.nix
    ./cli-tools.nix
  ];

  users.users.neg.maid = {};

  # Workaround: nix-maid hijacks ~/.config/systemd/user, breaking Home Manager.
  # We redirect nix-maid's config home for the activation service so it creates its systemd link
  # in a dummy directory, leaving the real one for Home Manager.
  systemd.user.services.maid-activation = {
    environment.XDG_CONFIG_HOME = "/home/neg/.cache/maid-systemd-workaround";
  };
}
