{
  lib,
  config,
  pkgs,
  ...
}:
let
  enable =
    (config.features.dev.enable or false)
    && (config.features.dev.ai.enable or false)
    && (config.features.dev.ai.omp.enable or false);
  ompWrapped = pkgs.writeShellScriptBin "omp" ''
    # Default: enable prewalk (plan with slow, implement with smol) — but only for `launch`,
    # never for subcommands (config, update, doctor, login, etc.).
    _omp_cmd="$(printf '%s\n' "$1" | sed -n '/^[a-z][a-z-]*$/p')"
    case " $* " in
      *" --no-prewalk "*|*" --no-prewalk") ;;
      *) case "$_omp_cmd" in
           ""|launch) set -- --prewalk "$@" ;;
         esac ;;
    esac
    exec ${lib.getExe pkgs.neg.omp} "$@"
  '';
in
lib.mkIf enable {
  environment.systemPackages = [ ompWrapped ];
}
