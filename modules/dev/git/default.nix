{
  pkgs,
  ...
}:
{
  environment.systemPackages = [
    pkgs.git-crypt # git-based encryption
    pkgs.git-extras # git extra commands
    pkgs.git-filter-repo # quickly rewrite git history
    pkgs.git-lfs # git extension for large files
    pkgs.git # my favorite DVCS
    pkgs.gh # GitHub CLI
    pkgs.gist # manage GitHub gists
  ];
}
