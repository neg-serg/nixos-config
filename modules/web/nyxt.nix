{
  lib,
  config,
  pkgs,
  inputs ? {},
  ...
}: let
  webEnabled = config.features.web.enable or false;
  nyxtEnabled = webEnabled && (config.features.web.nyxt.enable or false);
  boolEnv = name: let v = builtins.getEnv name; in v == "1" || v == "true" || v == "yes";
  customPkgs =
    if inputs ? nyxtQt
    then inputs.nyxtQt.packages.${pkgs.stdenv.hostPlatform.system}
    else null;
  pick = candidates: provider:
    if provider == null
    then null
    else let
      names = candidates;
    in
      if names == []
      then null
      else let
        n = builtins.head names;
      in
        if builtins.hasAttr n provider
        then provider.${n}
        else pick (builtins.tail names) provider;
  fromCustom = pick ["nyxt-qtwebengine" "nyxt-qt" "nyxt4" "nyxt"] customPkgs;
  chaoticPkgs =
    if boolEnv "HM_USE_CHAOTIC_NYXT" && inputs ? chaotic
    then (inputs.chaotic.packages.${pkgs.stdenv.hostPlatform.system} or null)
    else null;
  fromChaotic =
    if chaoticPkgs == null
    then null
    else if builtins.hasAttr "nyxt4" chaoticPkgs
    then chaoticPkgs.nyxt4
    else if builtins.hasAttr "nyxt-qtwebengine" chaoticPkgs
    then chaoticPkgs."nyxt-qtwebengine"
    else if builtins.hasAttr "nyxt-qt" chaoticPkgs
    then chaoticPkgs."nyxt-qt"
    else null;
  nyxtCandidate =
    if fromCustom != null
    then fromCustom
    else fromChaotic;
  fallback = pkgs.nyxt4-bin or pkgs.nyxt;
  package =
    if nyxtCandidate != null
    then nyxtCandidate
    else fallback;
in {
  config = lib.mkIf nyxtEnabled {
    environment.systemPackages = lib.mkAfter [package];
  };
}
