{
  config,
  lib,
  pkgs,
  ...
}:
let
  user = config.users.main.name or "neg";
  userData = lib.attrByPath [ "users" "users" user ] { } config;
  homeDir = lib.attrByPath [ "home" ] "/home/${user}" userData;
in
{
  # DeepSeek Harness (dsh) — agent harness, everything is a plugin.
  # Web UI served at http://127.0.0.1:3080 by default.
  systemd.user.services.dsh = {
    enable = true;
    description = "DeepSeek Harness (dsh) — agent harness Web UI";
    after = [ "network.target" ];
    wantedBy = [ "default.target" ];
    serviceConfig = {
      Type = "simple";
      WorkingDirectory = homeDir;
      # HMR plugin requires node --expose-internals (not allowed in NODE_OPTIONS)
      ExecStart = "${lib.getExe pkgs.nodejs} --expose-internals ${pkgs.neg.dsh}/lib/node_modules/@deepseek-ai/dsh/lib/bin.js web";
      Restart = "on-failure";
      RestartSec = 3;
    };
  };

  # Install the dsh CLI into the environment (PATH).
  environment.systemPackages = [
    pkgs.neg.dsh # DeepSeek Harness agent CLI (dsh)
  ];
}
