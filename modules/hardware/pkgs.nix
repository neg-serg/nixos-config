{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.overskride # bluetooth and obex client
  ];
}
