{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.delta # better diff tool
    pkgs.diff-so-fancy # human-friendly git diff pager
    pkgs.difftastic # syntax-aware diff
    pkgs.diffutils # classic diff utils
  ];
}
