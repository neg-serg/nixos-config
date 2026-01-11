{ pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.ddccontrol # ddc control
    pkgs.ddcutil # rule monitor params
    # pkgs.edid-decode # edid decoder and tester (removed from nixpkgs)
    pkgs.read-edid # tool to read and parse edid from monitors
  ];
}
