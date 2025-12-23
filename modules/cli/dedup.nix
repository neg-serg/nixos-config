{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.czkawka # find duplicate/similar files
    pkgs.fclones # fast content-based duplicate finder
    pkgs.jdupes # deduplicate identical files via hardlinks
    pkgs.rmlint # remove duplicates
  ];
}
