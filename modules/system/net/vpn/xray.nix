{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    xorg.xhost # Manage X server access from nekoray UI
    nekoray # GUI client for Xray/V2Ray cores
  ];
}
