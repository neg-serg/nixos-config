{ pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.ddcui # Qt GUI for DDC/CI monitor controls (ddcutil frontend, replaces ddccontrol)
    pkgs.ddcutil # rule monitor params
    pkgs.read-edid # tool to read and parse edid from monitors
  ];
}
