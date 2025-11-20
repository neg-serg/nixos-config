{
  lib,
  config,
  pkgs,
  inputs,
  ...
}: let
  inherit (pkgs.stdenv.hostPlatform) system;
  repoRoot = inputs.self;
  caches = import (repoRoot + "/nix/caches.nix");
  dropCache = url: url != "https://cache.nixos.org/";
  dropKey = key: key != "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=";
  extraSubstituters = lib.filter dropCache caches.substituters;
  extraTrustedKeys = lib.filter dropKey caches."trusted-public-keys";
  iosevkaNeg = inputs."iosevka-neg".packages.${system};
  perSystem = lib.genAttrs [system] (_: {inherit pkgs iosevkaNeg;});
  hmInputs = builtins.mapAttrs (_: input: input // {type = "derivation";}) {
    inherit (inputs) nupm;
  };
  mkHMArgs = import (repoRoot + "/flake/home/mkHMArgs.nix") {
    inherit lib perSystem hmInputs extraSubstituters extraTrustedKeys inputs;
    yandexBrowserInput = inputs."yandex-browser";
    inherit (inputs) nur;
  };
  extraArgs = mkHMArgs system;
  mainUser = config.users.main.name or "neg";
  hmModules = [
    (repoRoot + "/home/home.nix")
    inputs.stylix.homeModules.stylix
    inputs.chaotic.homeManagerModules.default
    inputs."sops-nix".homeManagerModules.sops
  ];
  cfgPath = repoRoot + "/home";
  userConfig = {
    _module.args.negPaths = extraArgs.negPaths;
    imports = hmModules;
    neg.hmConfigRoot = cfgPath;
    neg.repoRoot = repoRoot;
    neg.packagesRoot = repoRoot + "/packages";
  };
  extraSpecialArgs = extraArgs;
in {
  config = {
    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      inherit extraSpecialArgs;
      users.${mainUser} = userConfig;
    };
  };
}
