{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.droidcam # Linux client for DroidCam app
  ];
}
