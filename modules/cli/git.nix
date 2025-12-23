{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.mergiraf # AST-aware git merge driver
    pkgs.onefetch # pretty git repo summaries (used in fetch scripts)
    pkgs.tig # git TUI
  ];
}
