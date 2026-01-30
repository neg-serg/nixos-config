{
  lib,
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

  hasBraveSearchApi = builtins.pathExists ../../secrets/home/brave-search-api.env.sops;

  opencodeConfig = builtins.toJSON {
    "$schema" = "https://opencode.ai/config.json";
    plugin = [ "opencode-antigravity-auth@beta" ];
    provider = {
      google = {
        npm = "@ai-sdk/google";
        models = {
          antigravity-gemini-3-pro = {
            name = "Gemini 3 Pro (Antigravity)";
            limit = {
              context = 1048576;
              output = 65535;
            };
            modalities = {
              input = [
                "text"
                "image"
                "pdf"
              ];
              output = [ "text" ];
            };
            variants = {
              low = {
                thinkingLevel = "low";
              };
              high = {
                thinkingLevel = "high";
              };
            };
          };
          antigravity-gemini-3-flash = {
            name = "Gemini 3 Flash (Antigravity)";
            limit = {
              context = 1048576;
              output = 65536;
            };
            modalities = {
              input = [
                "text"
                "image"
                "pdf"
              ];
              output = [ "text" ];
            };
            variants = {
              minimal = {
                thinkingLevel = "minimal";
              };
              low = {
                thinkingLevel = "low";
              };
              medium = {
                thinkingLevel = "medium";
              };
              high = {
                thinkingLevel = "high";
              };
            };
          };
          antigravity-claude-sonnet-4-5 = {
            name = "Claude Sonnet 4.5 (Antigravity)";
            limit = {
              context = 200000;
              output = 64000;
            };
            modalities = {
              input = [
                "text"
                "image"
                "pdf"
              ];
              output = [ "text" ];
            };
          };
          antigravity-claude-sonnet-4-5-thinking = {
            name = "Claude Sonnet 4.5 Thinking (Antigravity)";
            limit = {
              context = 200000;
              output = 64000;
            };
            modalities = {
              input = [
                "text"
                "image"
                "pdf"
              ];
              output = [ "text" ];
            };
            variants = {
              low = {
                thinkingConfig = {
                  thinkingBudget = 8192;
                };
              };
              max = {
                thinkingConfig = {
                  thinkingBudget = 32768;
                };
              };
            };
          };
          antigravity-claude-opus-4-5-thinking = {
            name = "Claude Opus 4.5 Thinking (Antigravity)";
            limit = {
              context = 200000;
              output = 64000;
            };
            modalities = {
              input = [
                "text"
                "image"
                "pdf"
              ];
              output = [ "text" ];
            };
            variants = {
              low = {
                thinkingConfig = {
                  thinkingBudget = 8192;
                };
              };
              max = {
                thinkingConfig = {
                  thinkingBudget = 32768;
                };
              };
            };
          };
          gemini-2-5-flash = {
            name = "Gemini 2.5 Flash (Gemini CLI)";
            limit = {
              context = 1048576;
              output = 65536;
            };
            modalities = {
              input = [
                "text"
                "image"
                "pdf"
              ];
              output = [ "text" ];
            };
          };
          gemini-2-5-pro = {
            name = "Gemini 2.5 Pro (Gemini CLI)";
            limit = {
              context = 1048576;
              output = 65536;
            };
            modalities = {
              input = [
                "text"
                "image"
                "pdf"
              ];
              output = [ "text" ];
            };
          };
          gemini-3-flash-preview = {
            name = "Gemini 3 Flash Preview (Gemini CLI)";
            limit = {
              context = 1048576;
              output = 65536;
            };
            modalities = {
              input = [
                "text"
                "image"
                "pdf"
              ];
              output = [ "text" ];
            };
          };
          gemini-3-pro-preview = {
            name = "Gemini 3 Pro Preview (Gemini CLI)";
            limit = {
              context = 1048576;
              output = 65535;
            };
            modalities = {
              input = [
                "text"
                "image"
                "pdf"
              ];
              output = [ "text" ];
            };
          };
        };
      };
    };
    # MCP (Model Context Protocol) servers configuration
    mcp = {
      # GitHub code search via Vercel Grep
      gh_grep = {
        type = "remote";
        url = "https://mcp.grep.app";
        enabled = false;
      };
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
          GITHUB_PERSONAL_ACCESS_TOKEN = "{env:GITHUB_TOKEN}";
        };
        timeout = 5000;
      };
      # Google Maps integration
      google_maps = {
        type = "local";
        command = [
          "npx"
          "-y"
          "@modelcontextprotocol/server-google-maps"
        ];
        enabled = false;
        environment = {
          GOOGLE_MAPS_API_KEY = "{env:GOOGLE_MAPS_API_KEY}";
        };
        timeout = 5000;
      };
      # Brave Search integration
      brave_search = {
        type = "local";
        command = [
          "npx"
          "-y"
          "@modelcontextprotocol/server-brave-search"
        ];
        enabled = true;
        environment = {
          BRAVE_API_KEY = "{env:BRAVE_API_KEY}";
        };
        timeout = 5000;
      };
    };
  };
in
lib.mkIf enable (
  n.mkHomeFiles {
    ".config/opencode/opencode.json".text = opencodeConfig;
    # Shell init snippet to export BRAVE_API_KEY (sourced by zshrc)
    ".config/zsh/10-opencode-brave.zsh" = lib.mkIf hasBraveSearchApi {
      text = ''
        # Source Brave Search API key for OpenCode MCP
        if [[ -f "/run/user/1000/secrets/brave-search-api.env" ]]; then
          source "/run/user/1000/secrets/brave-search-api.env"
        fi
      '';
    };
  }
)
