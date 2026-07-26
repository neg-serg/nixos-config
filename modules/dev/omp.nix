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
  ompProxyApiKey = "REDACTED-API-KEY";
  ompProxyBaseUrl = "http://204.152.223.171:20128/v1";
  ompWrapped = pkgs.writeShellScriptBin "omp" ''
    export OPENAI_API_KEY="${ompProxyApiKey}"
    export OPENAI_BASE_URL="${ompProxyBaseUrl}"
    exec ${lib.getExe pkgs.neg.omp} "$@"
  '';
in
lib.mkIf enable {
  environment.systemPackages = [
    ompWrapped # OMP with proxy API endpoint
  ];
}
