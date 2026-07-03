{
  lib,
  pkgs,
  config,
  neg,
  impurity ? null,
  ...
}:
let
  n = neg impurity;
  enable =
    (config.features.dev.enable or false)
    && (config.features.dev.ai.enable or false)
    && (config.features.dev.ai.opencode.enable or false);

  deepseekSecretPath = "/run/secrets/deepseek-api";
  deepseekApiKey =
    if builtins.pathExists deepseekSecretPath
    then lib.strings.removeSuffix "\n" (builtins.readFile deepseekSecretPath)
    else "{env:DEEPSEEK_API_KEY}";
  githubSecretPath = "/run/secrets/github-token";
  githubToken =
    if builtins.pathExists githubSecretPath
    then lib.strings.removeSuffix "\n" (builtins.readFile githubSecretPath)
    else "{env:GITHUB_TOKEN}";

  opencodeConfig = builtins.toJSON {
    "$schema" = "https://opencode.ai/config.json";
    model = "deepseek/deepseek-v4-flash";
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
          };
          deepseek-v4-pro = {
            name = "DeepSeek V4 Pro";
            reasoning = true;
            options = {
              reasoningEffort = "high";
            };
            variants = {
              none = { reasoningEffort = "none"; };
              low = { reasoningEffort = "low"; };
              medium = { reasoningEffort = "medium"; };
              high = { reasoningEffort = "high"; };
            };
          };
        };
      };
    };
    mcp = {
      # MCP test server with various tools
      mcp_everything = {
        type = "local";
        command = [
          "npx"
          "-y"
          "@modelcontextprotocol/server-everything"
        ];
        enabled = true;
        timeout = 5000;
      };
      # Filesystem operations server
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
        timeout = 5000;
      };
      # GitHub repository integration
      github = {
        type = "local";
        command = [
          "npx"
          "-y"
          "@modelcontextprotocol/server-github"
        ];
        enabled = true;
        environment = {
          GITHUB_PERSONAL_ACCESS_TOKEN = githubToken;
        };
        timeout = 5000;
      };
      puppeteer = {
        type = "local";
        command = [
          "npx"
          "-y"
          "@modelcontextprotocol/server-puppeteer"
        ];
        enabled = true;
        timeout = 5000;
      };
      yt_dlp = {
        type = "local";
        command = [
          "npx"
          "-y"
          "@kevinwatt/yt-dlp-mcp@latest"
        ];
        enabled = true;
        environment = {
          YTDLP_DOWNLOADS_DIR = "/home/neg/dw";
        };
        timeout = 5000;
      };
      youtube = {
        type = "local";
        command = [
          "npx"
          "-y"
          "@anaisbetts/mcp-youtube"
        ];
        enabled = true;
        timeout = 5000;
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
      systemd.user.services.opencode-daemon = let
        opencodeServe = pkgs.writeShellScript "opencode-serve" ''
          export DEEPSEEK_API_KEY="$(${pkgs.coreutils}/bin/cat /run/secrets/deepseek-api 2>/dev/null || true)"
          export GITHUB_TOKEN="$(${pkgs.coreutils}/bin/cat /run/secrets/github-token 2>/dev/null || true)"
          exec ${pkgs.opencode}/bin/opencode serve
        '';
      in {
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
