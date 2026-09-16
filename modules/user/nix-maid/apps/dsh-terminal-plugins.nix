# Plugin roster shared by the terminal dsh profiles.
#
# Both terminal profiles run dsh-base plus this host/agent-plane set: the tui
# profile's Tianshu TUI (dsh-tui-ru.nix) and the martty profile's Martty TUI
# (dsh-martty.nix). One roster for both keeps their caretaker scripts from
# drifting — a row whose plugin is missing is what makes the next terminal
# start fail.
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
rec {
  plugins = [
    {
      name = "dsh-mode";
      path = ./dsh-mode;
    }
    {
      name = "dsh-session-tools";
      path = ./dsh-session-tools;
    }
    {
      name = "dsh-agent-usage-reminder";
      path = ./dsh-agent-usage-reminder;
    }
    {
      name = "dsh-compaction-todo-preserver";
      path = ./dsh-compaction-todo-preserver;
    }
    {
      name = "dsh-snapcompact";
      path = ./dsh-snapcompact;
    }
    {
      name = "dsh-rules-injector";
      path = ./dsh-rules-injector;
    }
    {
      name = "dsh-hashline";
      path = ./dsh-hashline;
    }
    # dsh-memory-extractor was removed with the web GUI (2026-09): it injected
    # the `memory` service, which this profile does not provide.
    {
      name = "dsh-debug";
      path = ./dsh-debug;
    }
    {
      name = "dsh-ast-grep";
      path = ./dsh-ast-grep;
    }
    {
      name = "dsh-checkpoint";
      path = ./dsh-checkpoint;
    }
    {
      name = "dsh-eval";
      path = ./dsh-eval;
    }
    {
      name = "dsh-hub";
      path = ./dsh-hub;
    }
    {
      name = "dsh-read-tags";
      path = ./dsh-read-tags;
    }
    {
      name = "dsh-desktop";
      path = ./dsh-desktop;
    }
    {
      name = "dsh-json-error-recovery";
      path = ./dsh-json-error-recovery;
    }
    {
      name = "dsh-keyword-detector";
      path = ./dsh-keyword-detector;
    }
    {
      name = "dsh-notepad-write-guard";
      path = ./dsh-notepad-write-guard;
    }
    {
      name = "dsh-delegate-task-retry";
      path = ./dsh-delegate-task-retry;
    }
    {
      name = "dsh-plan-format-validator";
      path = ./dsh-plan-format-validator;
    }
    {
      name = "dsh-task-resume-info";
      path = ./dsh-task-resume-info;
    }
    # Ported from the web profile (2026-09): the three are host/agent-plane with
    # no webServer/slots, and every service they inject exists here as well —
    # tool lifecycle hooks (secrets-masker), `ctx.sessionQuery` (recall; provided
    # by @deepseek-ai/dsh-session-query-sqlite, already mounted) and
    # `ctx.subprocess`/`ctx.tools` (plugin-vetting; dsh-subprocess-local).
    {
      name = "dsh-secrets-masker";
      path = ./dsh-secrets-masker;
    }
    {
      name = "dsh-plugin-recall";
      path = ./dsh-plugin-recall;
    }
    {
      name = "dsh-plugin-vetting";
      path = ./dsh-plugin-vetting;
    }
    # /worktree: drives the dsh-worktree helper (packages/local-bin) from inside
    # a session — create/list/remove the worktrees that isolate parallel dsh
    # sessions. Host/agent-plane: it injects `commands` and `subprocess`, both
    # mounted here (dsh-subprocess-local is what the bash tool already uses).
    {
      name = "dsh-worktree";
      path = ./dsh-worktree;
    }
    # /diff + show_diff: the diff-review surface. The tool declares the harness's
    # `card: "diff"` presenter (the same one the edit-approval preview uses), so
    # a review renders as structured red/green file diffs; the command is the
    # textual entry point. Injects tools + commands + subprocess.
    {
      name = "dsh-diff";
      path = ./dsh-diff;
    }
    # status line in the terminal title. Upstream Tianshu ships a scriptable
    # status line (StatusLineRunner) but never instantiates it in rc.29, and the
    # render slot above the input belongs to the TUI — so this drives OSC 1/2
    # with the output of packages/local-bin/bin/dsh-statusline, which speaks the
    # same documented protocol and plugs into the upstream runner unchanged if it
    # is ever wired. Injects subprocess only.
    {
      name = "dsh-statusline";
      path = ./dsh-statusline;
    }
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
    {
      name = "dsh-notify-input";
      path = ./dsh-notify-input;
    }
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
