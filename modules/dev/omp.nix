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
  ompWrapped = pkgs.writeShellScriptBin "omp" ''
    # Force DeepSeek models for all model roles regardless of OMP defaults/config.yml,
    # so the agent never falls back to a provider without an API key (e.g. cerebras,
    # zai-glm-4.7). Explicit --model/--smol/--slow/--plan flags still take precedence.
    export PI_SMOL_MODEL="''${PI_SMOL_MODEL:-deepseek/deepseek-v4-flash}" # implementation after prewalk
    export PI_PLAN_MODEL="''${PI_PLAN_MODEL:-deepseek/deepseek-v4-pro}"   # architectural planning
    export PI_SLOW_MODEL="''${PI_SLOW_MODEL:-deepseek/deepseek-v4-pro}"   # thorough reasoning

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
