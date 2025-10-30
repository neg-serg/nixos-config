{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.age
    pkgs.opensc
    pkgs.p11-kit
    pkgs.pcsc-tools
    pkgs.sops
    pkgs.ssh-to-age
  ];
}
