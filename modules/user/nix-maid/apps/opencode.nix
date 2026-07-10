{
  lib,
  pkgs,
  config,
  neg,
  ...
}:
let
  n = neg;
  enable =
    (config.features.dev.enable or false)
    && (config.features.dev.ai.enable or false)
    && (config.features.dev.ai.opencode.enable or false);

  deepseekSecretPath = "/run/secrets/deepseek-api";
  deepseekApiKey =
    if builtins.pathExists deepseekSecretPath then
      lib.strings.removeSuffix "\n" (builtins.readFile deepseekSecretPath)
    else
      "{env:DEEPSEEK_API_KEY}";
  opencodeConfig = builtins.toJSON {
    "$schema" = "https://opencode.ai/config.json";
    model = "deepseek/deepseek-v4-flash";
    plugin = [ "oh-my-openagent@latest" ];
    enabled_providers = [ "deepseek" ];
    provider = {
      deepseek = {
        npm = "@ai-sdk/openai-compatible";
        name = "DeepSeek";
        options = {
          baseURL = "https://api.deepseek.com/v1";
          apiKey = deepseekApiKey;
        };
        models = {
          deepseek-v4-flash = {
            name = "DeepSeek V4 Flash";
            reasoning = true;
            options.reasoningEffort = "high";
          };
          deepseek-v4-pro = {
            name = "DeepSeek V4 Pro";
            reasoning = true;
            options = {
              reasoningEffort = "high";
            };
            variants = {
              none = { reasoningEffort = "none"; };
              high = { reasoningEffort = "high"; };
              max = { reasoningEffort = "max"; };
            };
          };
        };
      };
    };
    mcp = {
      filesystem = {
        type = "local";
        command = [
          "npx"
          "-y"
          "@modelcontextprotocol/server-filesystem"
          "/home/neg"
          "/etc/nixos"
        ];
        enabled = true;
        timeout = 30000;
      };
      github = {
        type = "local";
        command = [
          "npx"
          "-y"
          "@modelcontextprotocol/server-github"
        ];
        enabled = true;
        timeout = 30000;
        environment = {
          GITHUB_PERSONAL_ACCESS_TOKEN = "{env:GITHUB_TOKEN}";
        };
      };
      puppeteer = {
        type = "local";
        command = [
          "npx"
          "-y"
          "@modelcontextprotocol/server-puppeteer"
        ];
        enabled = true;
        timeout = 30000;
      };
    };
  };
in
lib.mkIf enable (
  lib.mkMerge [
    (n.mkHomeFiles {
      ".config/opencode/opencode.json".text = opencodeConfig;
    })
    {
      systemd.user.services.opencode-daemon =
        let
          opencodeServe = pkgs.writeShellScript "opencode-serve" ''
            export DEEPSEEK_API_KEY="$(${pkgs.coreutils}/bin/cat /run/secrets/deepseek-api 2>/dev/null || true)"
            export GITHUB_TOKEN="$(${pkgs.coreutils}/bin/cat /run/secrets/github-token 2>/dev/null || true)"
            export PATH="${pkgs.nodejs}/bin:$PATH"
            exec ${pkgs.opencode}/bin/opencode serve
          '';
        in
        {
          description = "OpenCode AI coding agent daemon";
          after = [ "network.target" ];
          wantedBy = [ "default.target" ];
          serviceConfig = {
            Type = "simple";
            Restart = "on-failure";
            RestartSec = 10;
            ExecStart = "${opencodeServe}";
            Environment = "HOME=%h";
          };
        };
    }
  ]
)
