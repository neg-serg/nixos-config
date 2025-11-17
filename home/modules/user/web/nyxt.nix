{
  lib,
  pkgs,
  config,
  xdg,
  nyxt4 ? null,
  ...
}:
with lib;
  mkIf (config.features.web.enable && config.features.web.nyxt.enable) (let
    # Prefer Nyxt 4 provider (Qt/Blink if available). Fallback to local nyxt4-bin (Electron/Blink), else nixpkgs Nyxt (WebKitGTK).
    nyxtPkg =
      if nyxt4 != null
      then nyxt4
      else (pkgs.nyxt4-bin or pkgs.nyxt);
    dlDir = "${config.home.homeDirectory}/dw";
  in
    lib.mkMerge [
      {
        home.packages = config.lib.neg.pkgsList [
          nyxtPkg # Nyxt web browser
        ];
        warnings =
          lib.optional (nyxt4 == null && !(pkgs ? nyxt4-bin))
          "Nyxt Qt/Blink provider not found; using WebKitGTK (pkgs.nyxt). Provide `nyxtQt` input or a chaotic package attribute (nyxt-qtwebengine/nyxt-qt/nyxt4).";
      }
      (let
        tpl = builtins.readFile ./nyxt/init.lisp;
        rendered = lib.replaceStrings ["@DL_DIR@"] [dlDir] tpl;
      in
        xdg.mkXdgText "nyxt/init.lisp" rendered)
    ])
