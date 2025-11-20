{
  lib,
  perSystem,
  yandexBrowserInput,
  nur,
  inputs,
  hmInputs,
  extraSubstituters,
  extraTrustedKeys,
}: system: let
  pkgsForSystem = perSystem.${system}.pkgs or null;
in {
  inputs = hmInputs;
  inherit (perSystem.${system}) iosevkaNeg;
  # Prefer Nyxt 4 / QtWebEngine variant when available from chaotic
  nyxt4 = let
    inherit (builtins) hasAttr;
    # Prefer explicit custom provider if present in inputs as `nyxtQt`.
    customPkgs =
      if hasAttr "nyxtQt" inputs
      then (inputs.nyxtQt.packages.${system} or null)
      else null;
    fromCustom =
      if customPkgs == null
      then null
      else let
        candidates = ["nyxt-qtwebengine" "nyxt-qt" "nyxt4" "nyxt"];
        pick = names:
          if names == []
          then null
          else let
            n = builtins.head names;
          in
            if hasAttr n customPkgs
            then customPkgs.${n}
            else pick (builtins.tail names);
      in
        pick candidates;
    # Fallback to chaotic if it exposes a Qt/Blink variant and is explicitly enabled
    chaoticPkgs =
      if inputs ? chaotic
      then (inputs.chaotic.packages.${system} or null)
      else null;
    fromChaotic =
      if chaoticPkgs == null
      then null
      else if hasAttr "nyxt4" chaoticPkgs
      then chaoticPkgs.nyxt4
      else if hasAttr "nyxt-qtwebengine" chaoticPkgs
      then chaoticPkgs."nyxt-qtwebengine"
      else if hasAttr "nyxt-qt" chaoticPkgs
      then chaoticPkgs."nyxt-qt"
      else null;
  in
    if fromCustom != null
    then fromCustom
    else fromChaotic;
  # Flake cache settings for reuse in modules (single source of truth)
  caches = {
    substituters = extraSubstituters;
    trustedPublicKeys = extraTrustedKeys;
  };
  # Provide lazy providers to avoid evaluating inputs unless features enable them
  # Firefox addons via NUR
  faProvider = pkgs: (pkgs.extend nur.overlays.default).nur.repos.rycee.firefox-addons;
  # Lazy Yandex Browser provider
  yandexBrowserProvider = pkgs:
    yandexBrowserInput.packages.${pkgs.stdenv.hostPlatform.system};
  # GUI helpers
  qsProvider = pkgs: inputs.quickshell.packages.${pkgs.stdenv.hostPlatform.system}.default;
  rsmetrxProvider = pkgs: inputs.rsmetrx.packages.${pkgs.stdenv.hostPlatform.system}.default;
  # Provide xdg helpers directly to avoid _module.args fallback recursion
  xdg = import ../../home/modules/lib/xdg-helpers.nix {
    inherit lib;
    inherit (perSystem.${system}) pkgs;
  };
  systemdUser = import ../../home/modules/lib/systemd-user.nix {inherit lib;};
}
