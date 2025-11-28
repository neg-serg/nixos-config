{
  lib,
  config,
  pkgs,
  inputs,
  ...
}: let
  inherit (pkgs.stdenv.hostPlatform) system;
  # Resolve repo root via mkHMArgs to prefer a live checkout (/etc/nixos or NEG_REPO_ROOT) over the store copy.
  mkHMArgs = import (inputs.self + "/flake/home/mkHMArgs.nix") {
    inherit lib perSystem hmInputs extraSubstituters extraTrustedKeys inputs;
    yandexBrowserInput = inputs."yandex-browser";
    inherit (inputs) nur;
  };
  extraArgs = mkHMArgs system;
  repoRoot = extraArgs.negPaths.repoRoot;
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
  mainUser = config.users.main.name or "neg";
  hmModules = [
    (repoRoot + "/home/home.nix")
    inputs.stylix.homeModules.stylix
    inputs.chaotic.homeManagerModules.default
    inputs."sops-nix".homeManagerModules.sops
  ];
  cfgPath = extraArgs.negPaths.hmConfigRoot;
  userConfig = {
    _module.args.negPaths = extraArgs.negPaths;
    imports = hmModules;
    neg.hmConfigRoot = cfgPath;
    neg.repoRoot = repoRoot;
    neg.packagesRoot = extraArgs.negPaths.packagesRoot;
    programs.home-manager.enable = true;
    home-manager.backupFileExtension = ".bak";
    manual = {
      html.enable = false;
      json.enable = false;
      manpages.enable = true;
    };
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
