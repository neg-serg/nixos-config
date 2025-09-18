{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.dosbox # DOS emulator
    pkgs.dosbox-staging # dosbox-staging
    pkgs.dosbox-x # dosbox-x
  ];
}
