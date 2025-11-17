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
  hy3Pkg =
    if pkgsForSystem == null
    then null
    else if lib.hasAttrByPath ["hyprlandPlugins" "hy3"] pkgsForSystem
    then lib.getAttrFromPath ["hyprlandPlugins" "hy3"] pkgsForSystem
    else null;
  hy3Args =
    if hy3Pkg == null
    then {}
    else {
      rev = lib.attrByPath ["src" "rev"] null hy3Pkg;
      version = lib.attrByPath ["version"] null hy3Pkg;
      packages = lib.listToAttrs [
        {
          name = system;
          value = {hy3 = hy3Pkg;};
        }
      ];
    };
in {
  inputs = hmInputs;
  hy3 = hy3Args;
  inherit (perSystem.${system}) iosevkaNeg;
  # Prefer Nyxt 4 / QtWebEngine variant when available from chaotic
  nyxt4 = let
    inherit (builtins) hasAttr;
    # Cheap env parser to keep eval fast and optional
    boolEnv = name: let v = builtins.getEnv name; in v == "1" || v == "true" || v == "yes";
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
      if boolEnv "HM_USE_CHAOTIC_NYXT"
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
  iwmenuProvider = pkgs: inputs.iwmenu.packages.${pkgs.stdenv.hostPlatform.system}.default;
  bzmenuProvider = pkgs: inputs.bzmenu.packages.${pkgs.stdenv.hostPlatform.system}.default;
  rsmetrxProvider = pkgs: inputs.rsmetrx.packages.${pkgs.stdenv.hostPlatform.system}.default;
  # Rust raise utility (flake-utils defaultPackage)
  raiseProvider = pkgs: inputs.raise.defaultPackage.${pkgs.stdenv.hostPlatform.system};
  # Provide xdg helpers directly to avoid _module.args fallback recursion
  xdg = import ../modules/lib/xdg-helpers.nix {
    inherit lib;
    inherit (perSystem.${system}) pkgs;
  };
  systemdUser = import ../modules/lib/systemd-user.nix {inherit lib;};
}
