{
  config,
  pkgs,
  ...
}:
let
  inherit (config.lib.neg) homeDir;
  systemdUser = config.lib.neg.systemdUser;
in
{
  # OmniRouter — unified LLM API router, local mode.
  # Backend: ollama via OpenAI-compatible endpoint (OPENAI_BASE_URL).
  # Auth: OMNIROUTER_API_KEYS (default "omnirouter-local").
  systemd.user.services.omnirouter = systemdUser.mkUserService {
    enable = true;
    description = "OmniRouter - unified LLM API router (local mode, ollama backend)";
    presets = [
      "defaultWanted"
      "restartOnFailure"
    ];
    after = [ "network.target" ];
    serviceConfig = {
      Type = "simple";
      WorkingDirectory = "${homeDir}/.local/share/omnirouter";
      ExecStart = "${homeDir}/.local/share/omnirouter/venv/bin/uvicorn serverRouter.router:app --host 127.0.0.1 --port 8000";
      RestartSec = 3;
    };
    environment = {
      OPENAI_API_KEY = "ollama";
      OPENAI_BASE_URL = "http://localhost:11434/v1";
      OMNIROUTER_API_KEYS = "omnirouter-local";
      # grpcio C extension needs the gcc runtime (libstdc++.so.6), absent from NixOS unit env.
      LD_LIBRARY_PATH = "${pkgs.stdenv.cc.cc.lib}/lib";
    };
  };
}
