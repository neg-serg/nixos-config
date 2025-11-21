{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.age # modern age encryption CLI for sops/secrets
    pkgs.opensc # PKCS#11 tools for smart cards
    pkgs.p11-kit # manage PKCS#11 modules (dev/test)
    pkgs.pcsc-tools # pcsc_scan et al. for smartcard debugging
    pkgs.sops # Mozilla SOPS secrets editor
    pkgs.ssh-to-age # convert SSH keys to age recipients
  ];
}
