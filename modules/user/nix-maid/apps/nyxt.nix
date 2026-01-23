{
  lib,
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
      dlDir = "${config.users.users.neg.home}/dw";
      tpl = builtins.readFile ../web/nyxt/init.lisp;
      rendered = lib.replaceStrings [ "@DL_DIR@" ] [ dlDir ] tpl;
    in
    n.mkHomeFiles {
      ".config/nyxt/init.lisp".text = rendered;
    }
  );
}
