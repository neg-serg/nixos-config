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
  # Proxy endpoint — change via override if the IP changes
  proxyUrl = "http://204.152.223.171:20128/v1";
  # Model defaults — env vars, overrideable via omp config or CLI
  smolModel = "deepseek/deepseek-chat";
  slowModel = "deepseek/deepseek-v4-pro";
  planModel = "deepseek/deepseek-v4-pro";
  ompWrapped = pkgs.writeShellScriptBin "omp" ''
    export OPENAI_API_KEY="$(${lib.getExe' pkgs.coreutils "cat"} /run/user/1000/secrets/deepseek-api 2>/dev/null || true)"
    export OPENAI_BASE_URL="${proxyUrl}"
    # Model roles: env vars set defaults; omp config or --smol/--slow/--plan flags override
    export PI_SMOL_MODEL="''${PI_SMOL_MODEL:-${smolModel}}"
    export PI_SLOW_MODEL="''${PI_SLOW_MODEL:-${slowModel}}"
    export PI_PLAN_MODEL="''${PI_PLAN_MODEL:-${planModel}}"
    exec ${lib.getExe pkgs.neg.omp} "$@"
  '';
in
lib.mkIf enable {
  environment.systemPackages = [ ompWrapped ];
}
