{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.age
    pkgs.opensc
    pkgs.p11-kit
    pkgs.pcsctools
    pkgs.sops
    pkgs.ssh-to-age
  ];
}
