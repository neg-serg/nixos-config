{
  pkgs,
  config,
  ...
}:
let
  onDemand = import (config.lib.neg.path "lib/on-demand-app.nix") { inherit pkgs; };
in
{
  environment.systemPackages = [
    pkgs.age # modern age encryption CLI for sops/secrets
    (onDemand {
      name = "sops";
      attr = "sops";
    }) # Mozilla SOPS secrets editor, built on first use
    pkgs.ssh-to-age # convert SSH keys to age recipients
  ];
}
