{
  inputs,
  nixpkgs,
  ...
}: let
  inherit (nixpkgs) lib;

  hyprlandOverlay = system: (_: prev: let
    esc = lib.escapeShellArg;
    hyprInfo = inputs.hyprland.sourceInfo or {};
    hyprRev = hyprInfo.rev or "unknown";
    hyprRef = hyprInfo.ref or "";
    hyprBranch =
      if hyprRef != ""
      then hyprRef
      else hyprRev;
    hyprTag =
      if (builtins.match "^v[0-9].*" hyprRef) != null
      then hyprRef
      else "";
    hyprTagOrBranch =
      if hyprTag != ""
      then hyprTag
      else hyprBranch;
    hyprCommits = builtins.toString (hyprInfo.revCount or 0);
    hyprDate =
      hyprInfo.lastModifiedDate
      or (
        if hyprInfo ? lastModified
        then "unix:${builtins.toString hyprInfo.lastModified}"
        else "unknown"
      );
    hyprMessage =
      if hyprTag != ""
      then "Release ${hyprTag}"
      else "Flake build ${builtins.substring 0 7 hyprRev}";
    hyprlandBase =
      inputs.hyprland.packages.${system}.hyprland.override {wrapRuntimeDeps = false;};
    hyprland = hyprlandBase.overrideAttrs (old: {
      postPatch =
        (old.postPatch or "")
        + ''
          rm -f src/version.h
          HASH=${esc hyprRev} \
            BRANCH=${esc hyprBranch} \
            MESSAGE=${esc hyprMessage} \
            DATE=${esc hyprDate} \
            DIRTY= \
            TAG=${esc hyprTagOrBranch} \
            COMMITS=${esc hyprCommits} \
            ./scripts/generateVersion.sh
        '';
    });
  in {
    inherit hyprland;
    inherit (inputs.xdg-desktop-portal-hyprland.packages.${system}) xdg-desktop-portal-hyprland;
    hyprlandPlugins =
      prev.hyprlandPlugins
      // {
        hy3 = inputs.hy3.packages.${system}.hy3;
      };
  });

  mkPkgs = system:
    import nixpkgs {
      inherit system;
      overlays = [
        ((import ../packages/overlay.nix) inputs)
        (hyprlandOverlay system)
      ];
      config = {
        allowAliases = false;
        allowUnfreePredicate = pkg: let
          name = pkg.pname or (builtins.parseDrvName (pkg.name or "")).name;
          allowed = [
            "google-antigravity"
            "antigravity-fhs"
            "google-chrome"
            "hiddify-app"
          ];
        in
          builtins.elem name allowed;
      };
    };

  mkCustomPkgs = pkgs: import ../packages/flake/custom-packages.nix {inherit pkgs;};
  mkIosevkaNeg = system: inputs."iosevka-neg".packages.${system};
in {
  inherit mkPkgs mkCustomPkgs mkIosevkaNeg;
}
