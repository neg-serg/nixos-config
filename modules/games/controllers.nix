{pkgs, ...}: {
  services.udev.packages = [pkgs.dualsensectl];

  environment.systemPackages = [
    pkgs.dualsensectl # tool for controlling DualSense controllers
  ];
}
