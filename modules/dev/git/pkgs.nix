{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    jujutsu # jj: a Git-compatible VCS
    git-crypt # git-based encryption
    git-extras # git extra commands
    git-filter-repo # quickly rewrite git history
    git-lfs # git extension for large files
    git # my favorite DVCS
  ];
}
