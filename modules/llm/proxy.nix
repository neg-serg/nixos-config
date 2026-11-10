##
# Module: llm/proxy
# Purpose: OpenAI-compatible guard in front of llama-swap for the small tiers.
#
# llama-swap already swaps models and speaks the OpenAI API, but it cannot do
# three things this fleet needs, and all three were measured on the sysadmin
# bench (see /zero/ai/llama/bench-sysadmin):
#
#  1. Keep a request inside the slot's context window. llama-server answers
#     400 the moment the prompt does not fit, and a long agent chain reaches
#     that point silently — the 16k coder slot failed at ~24k prompt tokens.
#  2. Normalize the tool protocol for small models: they batch dependent
#     calls and invent values they should have read (0/3 chains before the
#     "one tool per turn" rule, 3/3 after), and they misread a tool result
#     wrapped as {"result": ...} — plain text with a `name` is what works.
#  3. Retry the llama-swap swap race (500 "group starting ... aborted", 502
#     "proxy error: EOF") by unloading and waiting, which llmctl does by hand.
#
# The guards are profile-driven: a model listed in `profiles` gets a context
# budget and the protocol fix; anything else passes through untouched. The
# default profile set mirrors the slots in llama-swap.nix, and `mini` is the
# 32k alias the small tiers should be reached through.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  enabled = config.lib.neg.enabled "llm";
  cfg = config.services.llm-proxy;
  configFile = pkgs.writeText "llm-proxy.json" (
    builtins.toJSON {
      upstream = cfg.upstream;
      host = cfg.host;
      port = cfg.port;
      defaults = cfg.defaults;
      profiles = cfg.profiles;
    }
  );
in
{
  options.services.llm-proxy = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = enabled;
      description = ''
        Run the llm-proxy context guard in front of llama-swap on :9300.
        Clients that want the guards point at the proxy; clients that do not
        keep talking to llama-swap directly.
      '';
    };
    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Bind address.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 9300;
      description = "Listen port.";
    };
    upstream = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:9292";
      description = "llama-swap base URL.";
    };
    defaults = lib.mkOption {
      type = lib.types.attrs;
      default = {
        # Per-model overridable guards. `reserve` is the completion headroom
        # kept out of the trimmed prompt; the rest are protocol knobs.
        ctx = 32768;
        reserve = 4096;
        keep_tool_results = 6;
        keep_last_messages = 8;
        single_tool = true;
        thinking = null;
        target = null;
      };
      description = "Default guard values for every model not listed in `profiles`.";
    };
    profiles = lib.mkOption {
      type = lib.types.attrs;
      default = {
        # Chat tiers: real windows from llama-swap.nix, so trimming only fires
        # when the slot itself would reject the request.
        "qwen3.8-27b-abliterated" = {
          ctx = 32768;
        };
        "qwen3.8" = {
          target = "qwen3.8-27b-abliterated";
          ctx = 32768;
        };
        "ru" = {
          target = "qwen3.8-27b-abliterated";
          ctx = 32768;
        };
        "gemma4-26b-abliterated" = {
          ctx = 32768;
        };
        "gemma4" = {
          target = "gemma4-26b-abliterated";
          ctx = 32768;
        };
        "devstral-small-2-24b" = {
          ctx = 32768;
        };
        "devstral" = {
          target = "devstral-small-2-24b";
          ctx = 32768;
        };
        "coder" = {
          target = "devstral-small-2-24b";
          ctx = 32768;
        };
        "qwen3.8-27b-bartowski" = {
          ctx = 16384;
        };
        "bart27b" = {
          target = "qwen3.8-27b-bartowski";
          ctx = 16384;
        };
        "qwen3.8-27b-unsloth" = {
          ctx = 32768;
        };
        "ud" = {
          target = "qwen3.8-27b-unsloth";
          ctx = 32768;
        };
        "qwen3.8-flash-next-abliterated" = {
          ctx = 131072;
        };
        "qwen3.8-flash" = {
          target = "qwen3.8-flash-next-abliterated";
          ctx = 131072;
        };
        # Small tiers: `mini` is the 32k entry point the fleet uses for them;
        # the vision slot itself keeps its native 64k.
        "qwen3-vl-8b-abliterated" = {
          ctx = 65536;
          single_tool = false;
        };
        "vision" = {
          target = "qwen3-vl-8b-abliterated";
          ctx = 65536;
          single_tool = false;
        };
        "mini" = {
          target = "qwen3-vl-8b-abliterated";
          ctx = 32768;
        };
        "falcon-h1-3b" = {
          ctx = 65536;
          single_tool = false;
        };
        "falcon" = {
          target = "falcon-h1-3b";
          ctx = 65536;
          single_tool = false;
        };
      };
      description = ''
        Per-model guards: `ctx` is the slot's context window, `target` rewrites
        the model name sent upstream (aliases), `single_tool` injects the
        one-tool-per-turn rule when `tools` are present, `thinking = false`
        pins chat_template_kwargs.enable_thinking.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.etc."llm-proxy/config.json".source = configFile;

    systemd.services.llm-proxy = config.lib.neg.systemdUser.mkSystemService {
      description = "llm-proxy — context guard and tool-protocol normalizer for llama-swap";
      presets = [ "restartOnFailure" ];
      wantedBy = [ "multi-user.target" ];
      after = [ "llama-swap.service" ];
      wants = [ "llama-swap.service" ];
      serviceConfig = {
        ExecStart = "${pkgs.neg.llm-proxy}/bin/llm-proxy --config /etc/llm-proxy/config.json";
        RestartSec = 3;
        DynamicUser = true;
      };
    };
  };
}
