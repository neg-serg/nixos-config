{pkgs, ...}: {
  environment.systemPackages = [pkgs.appimage-run]; # run AppImages directly
}
