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
#     own intended target (mini = inkling-2-mini) and changed nothing: no batched
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

  # One option of a guard profile: every key is optional and null means "not set
  # here". `defaults` and each `profiles` entry are stripped of nulls before they
  # reach the JSON, so an unset key never shadows a value from `defaults` or from
  # the proxy's own base set.
  mkOpt =
    type: default: description:
    lib.mkOption { inherit type default description; };
  guardModule = {
    options = {
      ctx =
        mkOpt (lib.types.nullOr lib.types.ints.positive) null
          "Context window of the slot, in tokens.";
      reserve =
        mkOpt (lib.types.nullOr lib.types.ints.unsigned) null
          "Completion headroom kept out of the trimmed prompt.";
      keep_tool_results =
        mkOpt (lib.types.nullOr lib.types.ints.unsigned) null
          "Tool-result groups kept when trimming.";
      keep_last_messages =
        mkOpt (lib.types.nullOr lib.types.ints.unsigned) null
          "Trailing turns kept when trimming.";
      single_tool = mkOpt (lib.types.nullOr lib.types.bool) null ''
        Inject the one-tool-per-turn rule when tools are present. Off in
        the base set, and skipped anyway when the client's own system
        prompt already asks for one action per turn.
      '';
      thinking =
        mkOpt (lib.types.nullOr lib.types.bool) null
          "Pin chat_template_kwargs.enable_thinking (null leaves it alone).";
      target = mkOpt (lib.types.nullOr lib.types.str) null "Model name to send upstream, for aliases.";
    };
  };

  # Mirrors the base set in the proxy's `load_config`; the generated JSON is
  # the authoritative copy, the Python one is the fallback for a file that
  # carries no `defaults` at all. `single_tool` is opt-in: on 2026-11-10 the
  # guard was measured against its own profile (mini = inkling-2-mini) with a
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

  # Built-in guards. The `profiles` option holds only the user's side, so these
  # merge key by key: a host that overrides one field would otherwise replace the
  # whole profile (NixOS picks a single definition per key when priorities
  # differ, and ctx/target would silently disappear).
  #
  # Most names share one shape: a context window, optionally an upstream target
  # (aliases) and the opt-in single-tool rule.
  guardGroup =
    ctx: extra: names:
    lib.genAttrs names (_: { inherit ctx; } // extra);
  builtinProfiles = lib.foldl' (a: b: a // b) { } [
    # Chat tiers: real windows from llama-swap.nix, so trimming only fires
    # when the slot itself would reject the request.
    (guardGroup 32768 { } [
      "qwen3.8-27b-abliterated"
      "qwen3.8-27b-unsloth"
      "inkling-2-mini"
      "inkling-2-mini-q4"
    ])
    (guardGroup 16384 { } [
      "qwen3.8-27b-vision"
      "qwen3.8-27b-bartowski"
      "inkling-2-mini-q3"
      "qwen3.8-4b"
    ])
    (guardGroup 32768 { target = "qwen3.8-27b-abliterated"; } [
      "qwen3.8"
      "ru"
      "commit"
    ])
    (guardGroup 16384 { target = "qwen3.8-27b-bartowski"; } [ "bart27b" ])
    (guardGroup 32768 { target = "qwen3.8-27b-unsloth"; } [ "ud" ])
    # Small tiers: `mini` is the 32k entry point the fleet uses for them, and
    # since 2026-11-21 that is the Inkling IQ3 tier. The `vision` alias moved
    # to the 27B on 2026-11-11 (its slot carries the mmproj); `vision-fast`
    # points at ornith-1.5-9b now that the 8B is gone.
    (guardGroup 32768 { target = "inkling-2-mini"; } [
      "inkling-mini"
      "mini"
    ])
    (guardGroup 16384 { target = "inkling-2-mini-q3"; } [ "inkling-q3" ])
    (guardGroup 32768 {
      target = "ornith-1.5-9b";
      single_tool = false;
    } [ "vision-fast" ])
    (guardGroup 16384
      {
        target = "qwen3.8-27b-vision";
        single_tool = false;
      }
      [
        "vision"
        "vision-27b"
      ]
    )
    (guardGroup 65536 { single_tool = false; } [ "falcon-h1-3b" ])
    (guardGroup 65536 {
      target = "falcon-h1-3b";
      single_tool = false;
    } [ "falcon" ])
    # The commit writers: the slots' real windows, so the guard trims only
    # requests the slot itself would reject. `commit` is the default writer's
    # alias (the 27B, `COMMIT_DEFAULT_MODEL`); `commit-4b` is the fast tier.
    (guardGroup 16384 { target = "qwen3.8-4b"; } [ "commit-4b" ])
  ];

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
    host = mkOpt lib.types.str "127.0.0.1" "Bind address.";
    port = mkOpt lib.types.port 9300 "Listen port.";
    upstream = mkOpt lib.types.str "http://127.0.0.1:9292" "llama-swap base URL.";
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
        `profiles.qwen3.8.single_tool = false` keeps the alias and the
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
