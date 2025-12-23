{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.borgbackup # deduplicating backup utility
    pkgs.restic # deduplicating backup CLI
  ];
}
