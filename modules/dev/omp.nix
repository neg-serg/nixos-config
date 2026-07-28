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
  # Model defaults — env vars, overrideable via omp config or CLI
  smolModel = "deepseek/deepseek-chat";
  slowModel = "deepseek/deepseek-v4-pro";
  planModel = "deepseek/deepseek-v4-pro";
  ompWrapped = pkgs.writeShellScriptBin "omp" ''
    # omp resolves deepseek/deepseek-chat (etc.) under the "kilo" provider,
    # which reads KILO_API_KEY.
    export KILO_API_KEY="$(${lib.getExe' pkgs.coreutils "cat"} /run/user/1000/secrets/deepseek-api 2>/dev/null || true)"
    # Model roles: env vars set defaults; omp config or --smol/--slow/--plan flags override
    export PI_SMOL_MODEL="''${PI_SMOL_MODEL:-${smolModel}}"
    export PI_SLOW_MODEL="''${PI_SLOW_MODEL:-${slowModel}}"
    export PI_PLAN_MODEL="''${PI_PLAN_MODEL:-${planModel}}"
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
