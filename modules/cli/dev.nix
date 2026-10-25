{ pkgs, ... }:
{
  environment.systemPackages = [
    # Git tools
    pkgs.worktrunk # git worktree manager (binary `wt`): create, switch and clean up worktrees

    # Encoding & hashing
    pkgs.qrencode # QR generator for clipboard helpers

    # Fetch/info tools
    pkgs.fastfetch # modern ASCII system summary
  ];
}
