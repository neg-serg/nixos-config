{ pkgs, ... }:
{
  services.udev.packages = [ pkgs.dualsensectl ]; # dualsense controller management tool

  environment.systemPackages = [
    pkgs.dualsensectl # tool for controlling DualSense controllers
  ];
}
