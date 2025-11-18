{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.neovim
    # pkgs.zeal
  ];
}
