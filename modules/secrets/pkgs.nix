{ pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.age # modern age encryption CLI for sops/secrets
    pkgs.sops # Mozilla SOPS secrets editor
    pkgs.ssh-to-age # convert SSH keys to age recipients
  ];
}
