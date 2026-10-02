# Dendritic module entry point — each domain composes its own submodules.
#
# Architecture (parallel-eval refactoring, Jul 2026):
#   domainFilter :: string -> bool  (passed via specialArgs)
#   Controls which domain modules are imported. Default imports all.
#   Each host/test config can pass a restrictive filter to skip unused
#   domains, reducing the evaluation tree and enabling more parallel
#   evaluation via nix-eval-jobs.
#
#   Example: a headless server passes `domainFilter = n: n != "user" && n != "games"`
#   and skips Hyprland, nix-maid, gaming modules (~90 files fewer to import).
{
  neg,
  domainFilter ? (_: true),
  ...
}:
{
  # The domain list is no longer written down here: one domain = one
  # subdirectory, and the walk is neg.importDir's job. Adding a domain means
  # creating the directory, naming it in flake/nixos.nix (allDomains) and
  # nothing else — this file and the per-domain aggregators hold no paths.
  #
  # domainFilter arrives as the entry-name filter, so the names it receives are
  # exactly the directory names it already knows.
  imports = neg.importDir {
    dir = ./.;
    includeDirs = true;
    nameFilter = domainFilter;
  };
}
