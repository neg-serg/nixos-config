{
  config,
  pkgs,
  ...
}:
let
  onDemand = import (config.lib.neg.path "lib/on-demand-app.nix") { inherit pkgs; };
in
{
  environment.systemPackages = [
    pkgs.git-crypt # git-based encryption
    pkgs.git-extras # git extra commands
    pkgs.git-filter-repo # quickly rewrite git history
    pkgs.git-lfs # git extension for large files
    pkgs.git # my favorite DVCS
    # GitHub CLI and its Actions TUI: needed for the occasional PR/issue
    # lookup, so both are launchers that build on first call.
    (onDemand {
      name = "gh";
      attr = "gh";
    })
    (onDemand {
      name = "gh-enhance";
      attr = "gh-enhance";
    })
    pkgs.gist # manage GitHub gists
  ];
}
