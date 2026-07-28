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
  ompProxyBaseUrl = "http://204.152.223.171:20128/v1";
  ompWrapped = pkgs.writeShellScriptBin "omp" ''
    # Read API key from sops-managed secret
    export OPENAI_API_KEY="$(${lib.getExe' pkgs.coreutils "cat"} /run/user/1000/secrets/deepseek-api 2>/dev/null || true)"
    export OPENAI_BASE_URL="${ompProxyBaseUrl}"
    exec ${lib.getExe pkgs.neg.omp} "$@"
  '';
in
lib.mkIf enable {
  environment.systemPackages = [
    ompWrapped # OMP with proxy API endpoint
  ];
}
