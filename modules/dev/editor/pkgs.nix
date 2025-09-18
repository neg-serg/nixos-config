{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.neovim
    pkgs.emacs
    # pkgs.zeal
  ];
}
