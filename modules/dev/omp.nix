{
  lib,
  config,
  pkgs,
  ...
}:
let
  enable =
    (config.lib.neg.enabled "dev")
    && (config.lib.neg.enabled "dev.ai")
    && (config.lib.neg.enabled "dev.ai.omp");
  ompWrapped = pkgs.writeShellScriptBin "omp" (
    builtins.readFile (
      pkgs.replaceVars ./omp/omp-wrapper.sh {
        ompExe = lib.getExe pkgs.neg.omp;
      }
    )
  );
in
lib.mkIf enable {
  environment.systemPackages = [ ompWrapped ];
}
