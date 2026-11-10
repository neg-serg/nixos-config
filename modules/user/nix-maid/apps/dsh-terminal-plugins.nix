# Plugin roster for the terminal dsh profile.
#
# The tui profile runs dsh-base plus this host/agent-plane set over the dsh-TUI
# front door (dsh-tui.nix) — a row whose plugin is missing is what makes the
# next terminal start fail.
#
# The user's own host/agent plugins, mounted by the web profile through its
# modules. A terminal profile carries only dsh-base + its terminal UI, so without
# these the agent there sees just the bootstrap catalog and none of the
# /mode // /fast // /rename family. Every entry is host/agent-plane (injects
# tools, commands or memory — no webServer/slots), so it mounts in a terminal
# profile unchanged; the web-only ones (widgets, osm, preview, live-stats,
# remote-web-ui, web-ui-settings, gui-tweaks, pet) stay out. The tail of the
# list is ported from the web profile: secrets-masker/recall/plugin-vetting
# carry no UI face and need no web runtime (see the note below).
# dsh-free-search is mounted as well, but through pnpm instead of the repo
# seed — the caretaker installs it and owns its English-market config row.
# dsh-find-plugin rides the same pnpm path but needs no row override: the
# package's own bundle patch mounts its row, so the caretaker only keeps it
# installed (registry `latest`, like the TUI bundle).
# Every plugin directory must be `git add`ed before the switch: the flake
# source is a git snapshot, so an untracked directory never reaches the store
# and the caretaker reports it missing while the row is already in the patch
# layer — a state that breaks the next terminal start.
{ lib, homeDir }:
let
  # The roster is an explicit allow-list (`{ name; path; }`, one directory per
  # plugin): do NOT derive it with `builtins.readDir` — that would change which
  # plugins mount. Interpolating the name keeps `path` a path literal (not
  # toString), so each directory stays in the store closure — see `seeds` below.
  mkPlugin = name: {
    inherit name;
    path = ./${name};
  };
in
rec {
  plugins = map mkPlugin [
    "dsh-mode"
    "dsh-session-tools"
    "dsh-agent-usage-reminder"
    "dsh-compaction-todo-preserver"
    "dsh-snapcompact"
    "dsh-rules-injector"
    "dsh-hashline"
    # dsh-memory-extractor was removed with the web GUI (2026-09): it injected
    # the `memory` service, which this profile does not provide.
    "dsh-debug"
    "dsh-ast-grep"
    "dsh-checkpoint"
    "dsh-eval"
    "dsh-hub"
    "dsh-read-tags"
    "dsh-desktop"
    "dsh-json-error-recovery"
    "dsh-keyword-detector"
    "dsh-notepad-write-guard"
    "dsh-delegate-task-retry"
    "dsh-plan-format-validator"
    "dsh-task-resume-info"
    # Ported from the web profile (2026-09): the three are host/agent-plane with
    # no webServer/slots, and every service they inject exists here as well —
    # tool lifecycle hooks (secrets-masker), `ctx.sessionQuery` (recall; provided
    # by @deepseek-ai/dsh-session-query-sqlite, already mounted) and
    # `ctx.subprocess`/`ctx.tools` (plugin-vetting; dsh-subprocess-local).
    "dsh-secrets-masker"
    "dsh-plugin-recall"
    "dsh-plugin-vetting"
    # /worktree: drives the dsh-worktree helper (packages/local-bin) from inside
    # a session — create/list/remove the worktrees that isolate parallel dsh
    # sessions. Host/agent-plane: it injects `commands` and `subprocess`, both
    # mounted here (dsh-subprocess-local is what the bash tool already uses).
    "dsh-worktree"
    # Herdr state reporting: maps agent/status + the approval/question
    # waterfalls onto `herdr pane report-agent`, so the pane shows up as a
    # first-class agent (working/idle/blocked) in the sidebar, notifications and
    # `herdr agent wait`, and publishes turn/tokens/session as display metadata
    # (`herdr pane report-metadata`) for scripts and `$token` sidebar rows.
    # Inert outside a Herdr pane (HERDR_ENV=1); injects `subprocess` only.
    # See modules/user/nix-maid/apps/herdr.nix.
    "dsh-herdr"
    # /diff + show_diff: the diff-review surface. The tool declares the harness's
    # `card: "diff"` presenter (the same one the edit-approval preview uses), so
    # a review renders as structured red/green file diffs; the command is the
    # textual entry point. Injects tools + commands + subprocess.
    "dsh-diff"
    # status line in the terminal title. The TUI renders its own in-frame status
    # line, so this drives OSC 1/2 from packages/local-bin-system (dsh-statusline),
    # which speaks the Claude-Code-compatible protocol (session JSON on stdin,
    # first stdout line is the line). Injects subprocess only.
    "dsh-statusline"
    # Notify the human when the turn *blocks* on them: the approval card and the
    # structured question. The TUI's own notifyOs covers finished work only
    # (subagent / workflow / background task — the three call sites in the
    # bundle), and both request events are waterfalls whose TUI handler resolves
    # while the card is up, so a listener appended after it never runs — the
    # plugin registers `prepend: true`, continues the waterfall with `next()`,
    # and reports a request that is still unresolved after the grace (an
    # auto-approved tool settles on the next microtask and stays silent). Writes
    # OSC 99/9 straight to stdout: control-only, never the text grid. Injects no
    # service — the host event bus is the only seam.
    "dsh-notify-input"
    # Ctrl+Alt+<digit> model switching in the TUI. The shortcut seam is public,
    # but the live channel is host-internal: the plugin imports its registry by
    # a relative path into the installed bundle (see the package header for the
    # upgrade check).
    "dsh-model-hotkeys"
  ];

  # Loader rows for the plugins above, mirroring the web profile's patch layer
  # (the row id is the package name; only memory-extractor carries config, which
  # is appended as its own row below).
  rows =
    lib.concatMapStrings (name: ''
      - insert:
          - id: ${name}
            name: ${name}
    '') (map (p: p.name) (lib.filter (p: p.name != "dsh-memory-extractor") plugins))
    + ''
      # Cross-session full-text search (the `recall` tool): the shipped base row
      # pins `path: ':memory:'` + `openAt: never`, so every ctx.sessionQuery search
      # fails with SESSION_QUERY_SEARCH_DISABLED. An id-targeted override points it
      # at a durable derived index and defers the SQLite open to the first search
      # (never `startup`: a cold index would rebuild on every session start).
      # Patch semantics replace the whole row config — the plugin's own schema
      # defaults fill in everything else.
      - id: session-query-sqlite
        config:
          path: ${homeDir}/.dsh/session-search.db
          openAt: first-search
    '';

  # `seed_pkg <name> <path>` lines for the caretaker scripts. Path interpolation
  # (not toString) registers each plugin directory as a build input, so the store
  # copy exists even for plugins no other module references — a toString-only
  # string leaves the path outside the closure and seed_pkg reports it missing.
  seeds = lib.concatMapStrings (p: "seed_pkg ${p.name} ${p.path}\n") plugins;

  # English market for dsh-free-search (the shipped default is lang zh +
  # bingMarket zh-CN, i.e. Chinese-first results). The plugin mounts through
  # `dsh.profile.bundles` — `dsh plugin add` registers it there and the package
  # ships its own patch layer — so this must be an id-targeted *override*, never
  # an `insert`: a second `web-search-free` insert is "duplicate loader entry id"
  # and the whole plugin tree fails to load (the tui profile was down on exactly
  # this until 2026-09-16).
  # Patch semantics replace the whole row config, so the keys the package's layer
  # sets are repeated here. 0.8.1 (the 0.2.0-era release) repeats `provider`,
  # `disabledEngines`, `lang` and `bingMarket`, and the plugin no longer needs a
  # `web` override at all: upstream removed the static
  # `- id: web  config: searchProvider: ddg` row (its commentary: a wholesale
  # config replacement from a bundle that can be disabled or skipped leaves a
  # dangling `searchProvider: ddg` with nothing registering `ddg` — "every web
  # search then failed with `configured web provider "ddg" is not registered`").
  # The plugin now takes `web.searchProvider` over at runtime when the field is
  # unset or still the shipped default, which is exactly the outcome this
  # override used to force, so the override (and its `fetchProvider` key) is
  # dropped with it.
  # Appended only when the package is actually installed: a row without its
  # plugin is what makes the next terminal start fail.
  searchRows = ''
    # dsh-free-search: keyless engines, English market (module: dsh-terminal-plugins.nix).
    - id: web-search-free
      config:
        provider: ddg
        disabledEngines: []
        lang: en
        bingMarket: en-US
  '';

  # Model policy for the terminal profile: the DeepSeek route (V4.1-only catalog
  # plus retry policy), the local llama-swap catalog, and the default model for
  # new sessions (each note follows below).
  #
  # DeepSeek provider policy for the terminal profile: retry a malformed stream
  # instead of closing the turn. The adapter aborts the whole turn when a
  # tool-call's accumulated arguments fail a strict JSON.parse — the error is
  # `tool input is invalid JSON`, code MALFORMED_RESPONSE. The provider's
  # default retry policy does not list that code (it retries EMPTY_RESPONSE,
  # RATE_LIMIT, SERVER, TIMEOUT and TRANSPORT — see
  # @deepseek-ai/dsh-llm/retry-policy, DEFAULT_RETRYABLE_CODES), so the turn
  # dies with a red `turn error` row that /resume replays forever. Observed
  # three times on this host (2026-10-09 x2, and 2026-10-12 session efbb8d9f
  # turn 26, where it killed the unattended music-tag pass mid-run); in the
  # same session 1173 durable tool calls carried valid arguments, so the
  # malformed emission is a rare generation glitch — exactly what a bounded
  # retry recovers, since a failed attempt is never committed to the log and
  # the step simply re-runs.
  #
  # This has to be an id-targeted cordis row: the base bundle's
  # `dsh-settings-file` row does not survive composition in the tui profile
  # (no settings.yaml provider is mounted), so the usual `llm-deepseek` user
  # settings section cannot carry the policy here. Patch semantics replace the
  # whole row config, so every key the base and dsh-TUI bundle layers set is
  # repeated (composed values as of 2026-10-12).
  #
  # The catalog is narrowed to V4.1-Flash on purpose: the shipped list also
  # offers `deepseek-v4-pro`, which carries V4-era capability metadata (text-only
  # input, no in-history system-prompt update). The row replaces the whole
  # provider config, so this `models` list is the complete picker catalog for the
  # route — a capability that is not repeated here is gone.
  #
  # The default-model row pins new sessions to the same V4.1 route. The caretaker
  # rewrites it on every rebuild and login, so a runtime switch (/model, /fast,
  # /effort) survives only until the next one.
  #
  # The local catalog used to live in `settings.yaml` under `llm-pi-ai`. dsh
  # 0.2.0-rc.2 removed that file: its one-time import renamed it to
  # `settings.yaml.imported` and rejected the `llm-pi-ai` section, which is
  # exactly why the local models dropped out of /model. The caretaker owns this
  # block, so a rebuild restores the route instead of depending on a hand edit
  # that the next profile-layer rewrite discards.
  llmRows = ''
    # llm-deepseek: V4.1-only catalog, MALFORMED_RESPONSE is retryable
    # (module: dsh-terminal-plugins.nix).
    - id: llm-deepseek
      config:
        apiKeyEnv: DEEPSEEK_API_KEY
        baseURL: !!js process.env.DEEPSEEK_BASE_URL
        thinking: enabled
        reasoningEffort: max
        models:
          - id: deepseek-flash
            name: DeepSeek-V41-Flash
            inputModalities:
              - text
              - image
            systemPromptUpdate: in-history
            toolUpdate: addition-only
        retryPolicy:
          mode: normal
          maxRetries: 3
          retryableCodes:
            - EMPTY_RESPONSE
            - RATE_LIMIT
            - SERVER
            - TIMEOUT
            - TRANSPORT
            - MALFORMED_RESPONSE
    # llama-swap: the local uncensored catalog on 127.0.0.1:9292 (Vulkan; see
    # modules/llm/llama-swap.nix). The route is OpenAI-compatible and takes no
    # real key — LLAMA_SWAP_API_KEY is a dummy credential that only satisfies
    # the adapter. The model list is explicit: dsh does not discover models for
    # a hand-declared route, so anything missing here has no picker entry.
    - id: llm-pi-ai
      config:
        providers:
          llama-swap:
            displayName: Local uncensored (llama-swap)
            api: openai-completions
            baseURL: http://127.0.0.1:9292/v1
            apiKeyEnv: LLAMA_SWAP_API_KEY
            defaultContextWindow: 32768
            defaultMaxTokens: 8192
            # A 22k-token agent prompt needs ~4.5 min of prefill here (~85
            # tok/s measured 2026-11-10; the single llama-server slot adds
            # queue time while another session or `llmctl` holds it). The
            # 300 s pi-ai default expired just before the first token, and
            # each retry re-ran the same prefill, so the 2026-11-10 turn died
            # after six 5-minute attempts. 30 min covers a near-full 128k
            # prompt (~26 min at that rate) without hanging on a dead stream.
            streamIdleTimeoutMs: 1800000
            # TIMEOUT is deliberately not retryable: with the long idle window
            # above it means the server is really stuck, and a retry replays
            # the same multi-minute wait. Transport errors and llama-swap swap
            # races still get two attempts.
            retryPolicy:
              mode: normal
              maxRetries: 2
              retryableCodes:
                - EMPTY_RESPONSE
                - SERVER
                - STREAM_CLOSED
                - TRANSPORT
                - MALFORMED_RESPONSE
            models:
              - id: qwen3.8-flash-next-abliterated
                name: Qwen3.8-Flash-Next 180B (thinking, 128k)
                # Serves with thinking (xhigh, 4096-token budget); a hard
                # question costs minutes at ~8 tok/s. See llama-swap.nix.
                contextWindow: 131072
              - id: gpt-oss-120b-abliterated
                name: gpt-oss-120b (RAM tier, slow prefill)
                contextWindow: 32768
              - id: qwen3.8-27b-abliterated
                name: Qwen3.8-27B abliterated (quality, RU)
                # 32k measured at 13.75 GiB with the desktop, 30.5 tok/s at a
                # 9.5k prompt (see modules/llm/llama-swap.nix).
                contextWindow: 32768
              - id: gemma4-26b-abliterated
                name: Gemma 4 26B abliterated
                contextWindow: 32768
              - id: qwen3-vl-8b-abliterated
                name: Qwen3-VL-8B abliterated (vision)
                contextWindow: 65536
                input:
                  - text
                  - image
              # Runs on the other machine (192.168.0.144, RX 7900 XTX): the
              # weights sit on /zero and are read over SMB, llama-swap starts the
              # container there on the first request over ssh. Cold start is
              # ~4 min, decode ~50 tok/s; the model unloads on TTL (15 min) or on
              # /model switch, which frees the remote card.
              - id: gyro-coder
                name: Gyro-Coder 125B (7900 XTX box, ~4 min cold)
                contextWindow: 65536
              # OrcaCyber Nano 1.0 — 27B vision-language on the same 7900 XTX
              # box (the second remote tier in llama-swap.nix). Stock ROCm
              # llama.cpp, DFlash2 drafter + mmproj, 32k context, ~42 tok/s,
              # ~30 s cold load. Vision goes through the mmproj, hence `image`.
              - id: nano
                name: OrcaCyber Nano 27B VL (7900 XTX, vision)
                contextWindow: 32768
                input:
                  - text
                  - image
          # ── free-tier fallbacks (2026-11-05) ───────────────────────────────
          # Declared unconditionally and key-gated at request time: an unset
          # key fails that route only, never the loader. `free-llm-check`
          # probes every route with a tool call and reports which are armed.
          # Keys live in ~/.config/dsh/free-llm.env, sourced by the dsh wrapper
          # (dsh.nix), which also routes Node's fetch through the local
          # sing-box HTTP inbound — gemini is blocked on a direct connection
          # from this region.
          #
          # pollinations: anonymous, no signup, one reply per 45 seconds per
          # IP — a last-resort single shot, not an agent loop.
          #
          # gemini: free tier of the Gemini API. gemini-3.6-flash is free of
          # charge and tool-capable, but the free tier trains on what it is
          # sent — do not put private code through it. 3.7/3.8 do not answer on
          # this key's free tier (requests hang), so 3.6 is the newest usable.
          pollinations:
            displayName: Pollinations (free, no key)
            api: openai-completions
            baseURL: https://text.pollinations.ai/openai
            apiKeyEnv: POLLINATIONS_API_KEY
            defaultContextWindow: 32768
            defaultMaxTokens: 8192
            models:
              - id: openai-fast
                name: GPT-OSS 20B (free, 1 req/45s)
                contextWindow: 32768
          gemini:
            displayName: Gemini API (free tier)
            api: openai-completions
            baseURL: https://generativelanguage.googleapis.com/v1beta/openai/
            apiKeyEnv: GEMINI_API_KEY
            defaultContextWindow: 1048576
            defaultMaxTokens: 65536
            models:
              - id: gemini-3.6-flash
                name: Gemini 3.6 Flash (free tier)
                contextWindow: 1048576
                input:
                  - text
                  - image
              - id: gemini-3.5-flash-lite
                name: Gemini 3.5 Flash-Lite (free tier)
                contextWindow: 1048576
                input:
                  - text
                  - image
    # agent-default-model: deployment default for new sessions (module:
    # dsh-terminal-plugins.nix). Runtime switches revert on the next rebuild or
    # login, when the caretaker restores this row.
    - id: agent-default-model
      config:
        provider: deepseek-official
        model: deepseek-flash
        reasoningEffort: high
  '';
}
