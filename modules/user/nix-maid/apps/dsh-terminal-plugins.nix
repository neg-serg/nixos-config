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
# Every plugin directory must be `git add`ed before the switch: the flake
# source is a git snapshot, so an untracked directory never reaches the store
# and the caretaker reports it missing while the row is already in the patch
# layer — a state that breaks the next terminal start.
{ lib }:
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
    # /diff + show_diff: the diff-review surface. The tool declares the harness's
    # `card: "diff"` presenter (the same one the edit-approval preview uses), so
    # a review renders as structured red/green file diffs; the command is the
    # textual entry point. Injects tools + commands + subprocess.
    "dsh-diff"
    # status line in the terminal title. The TUI renders its own in-frame status
    # line, so this drives OSC 1/2 from packages/local-bin/bin/dsh-statusline,
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
  ];

  # Loader rows for the plugins above, mirroring the web profile's patch layer
  # (the row id is the package name; only memory-extractor carries config, which
  # is appended as its own row below).
  rows = lib.concatMapStrings (name: ''
    - insert:
        - id: ${name}
          name: ${name}
  '') (map (p: p.name) (lib.filter (p: p.name != "dsh-memory-extractor") plugins));

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
  # sets are repeated here, and the `web` override keeps `fetchProvider` —
  # dropping it re-registers web-fetch-http as a duplicate loader entry.
  # Appended only when the package is actually installed: a row without its
  # plugin is what makes the next terminal start fail.
  searchRows = ''
    # dsh-free-search: keyless engines, English market (module: dsh-terminal-plugins.nix).
    - id: web-search-free
      config:
        provider: ddg
        lang: en
        bingMarket: en-US
    - id: web
      config:
        searchProvider: ddg
        fetchProvider: http
  '';
}
