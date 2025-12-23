{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.qrencode # QR generator for clipboard helpers
    pkgs.rhash # hash sums calculator
  ];
}
