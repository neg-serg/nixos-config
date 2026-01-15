{
  lib,
  pkgs,
  config,
  neg,
  impurity ? null,
  ...
}:
let
  n = neg impurity;
in
{
  config = lib.mkIf (config.features.web.enable && config.features.web.nyxt.enable) (
    let
      nyxt4 = null;
      dlDir = "${config.users.users.neg.home}/dw";
      tpl = builtins.readFile ../web/nyxt/init.lisp;
      rendered = lib.replaceStrings [ "@DL_DIR@" ] [ dlDir ] tpl;
    in
    lib.mkMerge [
      {
        warnings =
          lib.optional (nyxt4 == null && !(pkgs ? nyxt4-bin))
            "Nyxt Qt/Blink provider not found; using WebKitGTK (pkgs.nyxt). Provide `nyxtQt` input or a chaotic package attribute (nyxt-qtwebengine/nyxt-qt/nyxt4)."; # Infinitely extensible web-browser (with Lisp development ...
      }
      (n.mkHomeFiles {
        ".config/nyxt/init.lisp".text = rendered;
      })
    ]
  );
}
