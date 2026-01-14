{
  lib,
  pkgs,
  config,
  ...
}:
let
  wantHxtools = config.features.dev.pkgs.misc or false;
  monitoringEnabled = config.roles.monitoring.enable or false;
in
{
  environment.systemPackages = [
    pkgs.jujutsu # jj: a Git-compatible VCS
    pkgs.git-crypt # git-based encryption
    pkgs.git-extras # git extra commands
    pkgs.git-filter-repo # quickly rewrite git history
    pkgs.bfg-repo-cleaner # BFG: fast Git history cleaner
    pkgs.git-lfs # git extension for large files
    # pkgs.git-annex # moved to devShells.gitops
    pkgs.git # my favorite DVCS
    pkgs.act # run GitHub Actions locally
    pkgs.gh # GitHub CLI
    pkgs.gist # manage GitHub gists
  ]
  ++ lib.optionals (wantHxtools && (!monitoringEnabled)) [
    pkgs.hxtools # hx* git and stats helpers (git-forest, git-blame-stats, git-logsortbychgsize)
  ];
}
