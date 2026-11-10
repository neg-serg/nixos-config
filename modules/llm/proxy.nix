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
#  2. Normalize the tool protocol: a tool result wrapped as {"result": ...} is
#     unwrapped to plain text with a `name`, which is what small models read
#     correctly, and the "one tool per turn" rule is available per profile.
#     The rule is off by default — it was measured on 2026-11-10 against its
#     own intended target (mini = qwen3-vl-8b) and changed nothing: no batched
#     turns in either arm, 0/6 tasks passed with and without it. A profile has
#     to ask for it until something shows a case where it pays.
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
  cfg = config.services.llm-proxy;

  # One guard profile. Every key is optional and null means "not set here":
  # `defaults` and each `profiles` entry are stripped of nulls before they
  # reach the JSON, so an unset key never shadows a value from `defaults` or
  # from the proxy's own base set.
  guardModule = {
    options = {
      ctx = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.positive;
        default = null;
        description = "Context window of the slot, in tokens.";
      };
      reserve = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.unsigned;
        default = null;
        description = "Completion headroom kept out of the trimmed prompt.";
      };
      keep_tool_results = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.unsigned;
        default = null;
        description = "Tool-result groups kept when trimming.";
      };
      keep_last_messages = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.unsigned;
        default = null;
        description = "Trailing turns kept when trimming.";
      };
      single_tool = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        description = ''
          Inject the one-tool-per-turn rule when tools are present. Off in
          the base set, and skipped anyway when the client's own system
          prompt already asks for one action per turn.
        '';
      };
      thinking = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        description = "Pin chat_template_kwargs.enable_thinking (null leaves it alone).";
      };
      target = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Model name to send upstream, for aliases.";
      };
    };
  };

  # Mirrors the base set in the proxy's `load_config`; the generated JSON is
  # the authoritative copy, the Python one is the fallback for a file that
  # carries no `defaults` at all. `single_tool` is opt-in: on 2026-11-10 the
  # guard was measured against its own profile (mini = qwen3-vl-8b) with a
  # client prompt that does not ask for one command per turn — 0 batched
  # turns out of 54 with the rule and out of 36 without, 0/6 tasks passed in
  # both arms. It has not earned a default-on, so a profile asks for it.
  baseGuards = {
    ctx = 32768;
    reserve = 4096;
    keep_tool_results = 6;
    keep_last_messages = 8;
    single_tool = false;
    thinking = null;
    target = null;
  };
  stripNulls = lib.filterAttrs (_: v: v != null);

  # Built-in guards. The `profiles` option holds only the user's side, so
  # these merge key by key: a host that overrides one field would otherwise
  # replace the whole profile (NixOS picks a single definition per key when
  # priorities differ, and ctx/target would silently disappear).
  builtinProfiles = {
    # Chat tiers: real windows from llama-swap.nix, so trimming only fires
    # when the slot itself would reject the request.
    "qwen3.8-27b-abliterated".ctx = 32768;
    "qwen3.8" = {
      target = "qwen3.8-27b-abliterated";
      ctx = 32768;
    };
    "ru" = {
      target = "qwen3.8-27b-abliterated";
      ctx = 32768;
    };
    "gemma4-26b-abliterated".ctx = 32768;
    "gemma4" = {
      target = "gemma4-26b-abliterated";
      ctx = 32768;
    };
    "devstral-small-2-24b".ctx = 32768;
    "devstral" = {
      target = "devstral-small-2-24b";
      ctx = 32768;
    };
    "coder" = {
      target = "devstral-small-2-24b";
      ctx = 32768;
    };
    "qwen3.8-27b-bartowski".ctx = 16384;
    "bart27b" = {
      target = "qwen3.8-27b-bartowski";
      ctx = 16384;
    };
    "qwen3.8-27b-unsloth".ctx = 32768;
    "ud" = {
      target = "qwen3.8-27b-unsloth";
      ctx = 32768;
    };
    "qwen3.8-flash-next-abliterated".ctx = 131072;
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

  wireProfiles = lib.mapAttrs (
    name: override: (builtinProfiles.${name} or { }) // stripNulls override
  ) (builtinProfiles // cfg.profiles);

  configFile = pkgs.writeText "llm-proxy.json" (
    builtins.toJSON {
      upstream = cfg.upstream;
      host = cfg.host;
      port = cfg.port;
      defaults = baseGuards // stripNulls cfg.defaults;
      profiles = wireProfiles;
    }
  );
in
{
  options.services.llm-proxy = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Run the llm-proxy context guard in front of llama-swap on :9300.
        Off by default: the trimming guard pays for itself only when a
        request would otherwise overflow the slot (measured 2026-11-10: a
        150k-character prompt is rejected with 400 directly and answered
        after trimming through the proxy), while the swap-race retry and
        the tool protocol add nothing that llama-swap and llmctl do not
        already do. Enable it per host when long sessions are expected;
        llmctl and the bench fall back to llama-swap when it is down.
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
      type = lib.types.submodule guardModule;
      default = { };
      description = ''
        Guard values for every model not listed in `profiles`, as typed
        overrides of the base set (ctx 32768, reserve 4096, keep 6 tool
        results and 8 turns, single-tool rule on, nothing pinned).
      '';
    };
    profiles = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule guardModule);
      default = { };
      description = ''
        Per-model guards, merged key by key over the built-in set, so
        overriding one field keeps the rest of the profile:
        `profiles.devstral.single_tool = false` keeps the alias and the
        context window. `ctx` is the slot's context window, `target`
        rewrites the model name sent upstream (aliases), `single_tool`
        injects the one-tool-per-turn rule when `tools` are present,
        `thinking = false` pins chat_template_kwargs.enable_thinking.
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
        # The proxy is pure Python over loopback: it reads one JSON config and
        # speaks HTTP to llama-swap. Nothing else in the system is its business.
        # MemoryDenyWriteExecute is safe here (unlike llama-swap's RADV JIT) —
        # CPython never maps writable-executable pages.
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        NoNewPrivileges = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        ProtectClock = true;
        ProtectHostname = true;
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        # AF_UNIX stays for the resolver (a hostname upstream would need it).
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        SystemCallFilter = [ "@system-service" ];
        CapabilityBoundingSet = [ "" ];
      };
    };
  };
}
