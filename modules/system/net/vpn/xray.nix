{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.xorg.xhost # Manage X server access from nekoray UI
    pkgs.nekoray # GUI client for Xray/V2Ray cores
  ];
}
