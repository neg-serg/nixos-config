{ pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.scrcpy # Android device display/control over USB/TCP (GTK-free replacement for droidcam)
  ];
}
