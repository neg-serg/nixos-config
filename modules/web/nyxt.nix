{
  lib,
  config,
  pkgs,
  inputs ? { },
  ...
}:
let
  webEnabled = config.features.web.enable or false;
  nyxtEnabled = webEnabled && (config.features.web.nyxt.enable or false);
  customPkgs =
    if inputs ? nyxtQt then inputs.nyxtQt.packages.${pkgs.stdenv.hostPlatform.system} else null;
  pick =
    candidates: provider:
    if provider == null then
      null
    else
      let
        names = candidates;
      in
      if names == [ ] then
        null
      else
        let
          n = builtins.head names;
        in
        if builtins.hasAttr n provider then provider.${n} else pick (builtins.tail names) provider;
  fromCustom = pick [ "nyxt-qtwebengine" "nyxt-qt" "nyxt4" "nyxt" ] customPkgs;

  nyxtCandidate = fromCustom;
  fallback = pkgs.nyxt4-bin or pkgs.nyxt; # Infinitely extensible web-browser (with Lisp development ...
  package = if nyxtCandidate != null then nyxtCandidate else fallback;
in
{
  config = lib.mkIf nyxtEnabled {
    environment.systemPackages = lib.mkAfter [ package ]; # Keyboard-centric, Common Lisp-extensible browser
  };
}
