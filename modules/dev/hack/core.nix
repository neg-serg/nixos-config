{
  lib,
  config,
  pkgs,
  ...
}:
let
  hackLib = import ./lib.nix { inherit lib config; };
  flags = config.features.dev.hack.core or { };
  groups = {
    secrets = [
      pkgs.gitleaks # scan repos/binaries for leaked secrets
      pkgs.git-secrets # server-side hook toolkit preventing commits w/ secrets
    ];
    reverse = [
      pkgs.capstone # multi-arch disassembly engine + CLI
    ];
    crawl = [
      pkgs.katana # fast web crawler for recon
    ];
  };
# _packages = hackLib.filterPackages (hackLib.mkGroupPackages flags groups);
in
{
  config = lib.mkIf hackLib.enabled {
    # environment.systemPackages = lib.mkAfter packages; # Moved to devShells.pentest
  };
}
