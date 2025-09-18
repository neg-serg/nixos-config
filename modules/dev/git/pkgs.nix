{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.jujutsu # jj: a Git-compatible VCS
    pkgs.git-crypt # git-based encryption
    pkgs.git-extras # git extra commands
    pkgs.git-filter-repo # quickly rewrite git history
    pkgs.git-lfs # git extension for large files
    pkgs.git # my favorite DVCS
  ];
}
