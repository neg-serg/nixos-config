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

  # dsh-tianshu-tui hardcodes its UI in Chinese with no language switch.
  # Assets below localize it to Russian: the translation map (i18n.json) and
  # the idempotent patcher (patch.mjs). gen.mjs regenerates the map against a
  # newer bundle when the plugin is upgraded.
  i18nJson = ./dsh-tui-ru-assets/i18n.json;
  patcher = ./dsh-tui-ru-assets/patch.mjs;
  # The neg look for the TUI itself: the built-in palettes are upstream themes
  # (cobalt/graphite/pastel/...), none of them the muted navy/teal/violet the
  # rest of the system uses (files/kitty/theme.conf, neg.omp.json). The TUI
  # loads custom themes from ~/.dsh-tui/themes/*.json and references them as
  # `custom:<name>`.
  themeJson = ./dsh-tui-ru-assets/themes/neg.json;

  # Patch every installed dsh-tianshu-tui bundle under ~/.dsh/profiles.
  # Idempotent (marker file); safe to run as root from an activation script.
  runPatch = pkgs.writeShellScript "dsh-tui-ru-patch" ''
    set +e
    for bundle in ${homeDir}/.dsh/profiles/*/node_modules/@huiliyi37/dsh-tianshu-tui/lib/index.js; do
      [ -f "$bundle" ] || continue
      ${lib.getExe pkgs.nodejs} ${patcher} ${i18nJson} "$bundle" \
        || echo "dsh-tui-ru: patch failed for $bundle" >&2
    done
    exit 0
  '';

  # The TUI profile's caretaker. Three things have to hold for the terminal UI
  # to work on this harness, and pnpm undoes two of them on every install:
  #
  # 1. dsh-tianshu-tui must be recent enough for the installed harness. Releases
  #    <= 0.1.2-rc.6 read `session.events`, an array the 0.1.5 Session no longer
  #    exposes, so the TUI died at startup with
  #    "attach failed: TypeError: session.events is not iterable"; the rc.29 line
  #    reads the current session face (the same break the plugin family hit).
  # 2. The profile's @deepseek-ai tree must BE the harness tree. pnpm installs
  #    the TUI plugin's own peer copies (0.1.2-rc.x), and those ship an older
  #    agent-presets schema — the shipped `standard` preset then fails to mount
  #    ("$.prefix missing required value"). Linking the harness tree keeps one
  #    instance per package (the web profile used the same relink before it was
  #    removed in 2026-09).
  # 3. The base default preset is `standard`, which the harness build removes
  #    (packages/dsh/default.nix): the profile fallback below names `neg`, and the
  #    TUI's own hardcoded DEFAULT_PRESET_ID is rewritten to `neg` by the
  #    translation patcher (dsh-tui-ru-assets/patch.mjs) — otherwise every start
  #    warns that the default preset did not apply. settings.yaml still wins over
  #    the row's fallback.
  # The profile ships `cordis.patch.yml` as an empty list; rows must replace
  # that `[]`, not be appended after it (a second YAML root node is a parse
  # error). Idempotent through its own marker comment.
  # The user's own host/agent plugins, mounted by the web profile through its
  # modules. The TUI profile carries only dsh-base + the terminal UI, so without
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
  # layer — a state that breaks the next TUI start.
  tuiPlugins = [
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
  tuiPluginRows = lib.concatMapStrings (name: ''
    - insert:
        - id: ${name}
          name: ${name}
  '') (map (p: p.name) (lib.filter (p: p.name != "dsh-memory-extractor") tuiPlugins));

  # Mount + English market for dsh-free-search (the shipped default is lang zh +
  # bingMarket zh-CN, i.e. Chinese-first results). Rows are spelled out rather
  # than relying on the plugin's bundled patch: `dsh plugin add` registers the
  # package as a dependency but not in `dsh.profile.bundles`, so that layer never
  # applies. The `web` row override must keep `fetchProvider` — patch semantics
  # replace the whole row config, and dropping it re-registers web-fetch-http as
  # a duplicate loader entry. Appended only when the package is actually
  # installed: a row without its plugin is what makes the next TUI start fail.
  tuiSearchRows = ''
    # dsh-free-search: keyless engines, English market (module: dsh-tui-ru.nix).
    - insert:
        - id: web-search-free
          name: dsh-free-search
          config:
            lang: en
            bingMarket: en-US
    - id: web
      config:
        searchProvider: ddg
        fetchProvider: http
  '';

  # The profile ships `cordis.patch.yml` as an empty list; rows must replace
  # that `[]` (a second YAML root node is a parse error). The caretaker rewrites
  # the header comments plus its own row, so a hand-edited or half-written file
  # heals on the next run.
  presetPatch = pkgs.writeText "dsh-tui-preset-patch.py" ''
    import sys

    path = sys.argv[1]
    MARKER_PRESET = "# dsh-tui-ensure: default preset"
    MARKER_RUNTIME = "# dsh-tui-ensure: code runtime"
    MARKER_PLUGINS = "# dsh-tui-ensure: plugin rows"
    rows_path = sys.argv[2] if len(sys.argv) > 2 else None
    plugin_rows = []
    if rows_path is not None:
        with open(rows_path, encoding="utf-8") as f:
            plugin_rows = [line.rstrip("\n") for line in f if line.strip()]
    BLOCKS = [
        (
            MARKER_PRESET,
            [
                MARKER_PRESET + " — the shipped `standard` is removed from the harness build, so the",
                "# fallback must name a preset that exists (settings.yaml still overrides it).",
                "- id: agent-presets",
                "  config:",
                "    default: neg",
            ],
        ),
        (
            MARKER_PLUGINS,
            [MARKER_PLUGINS] + plugin_rows,
        ),
        (
            MARKER_RUNTIME,
            [
                MARKER_RUNTIME + " — the neg preset promotes the agent to Code Mode",
                "# (tool-bootstrap `promotedPresentation: code`), and dsh-tools refuses",
                "# mode \"code\" without a ctx.codeRuntime implementation. The web profile",
                "# mounts it; the TUI profile's bundles (dsh-base + the tui plugin) do not.",
                "- insert:",
                "    - id: code-runtime",
                "      name: '@deepseek-ai/dsh-code-runtime-worker-thread'",
            ],
        ),
    ]

    with open(path, encoding="utf-8") as f:
        src = f.read()

    lines = src.split("\n")
    header, kept, index = [], [], 0
    while index < len(lines):
        line = lines[index]
        owned = next((block for marker, block in BLOCKS if marker in line), None)
        if owned is not None:
            # Skip this block: its marker line plus everything up to the next
            # block we own (or EOF). Content-based skipping would leave a stale
            # or malformed block behind — the loader then dies on a duplicate
            # entry id.
            index += 1
            while index < len(lines) and not any(marker in lines[index] for marker, _ in BLOCKS):
                index += 1
            continue
        if line.strip() == "[]":
            index += 1
            continue
        (header if not kept and line.startswith("#") else kept).append(line)
        index += 1

    body = "\n".join(header).rstrip("\n")
    for _, block in BLOCKS:
        body += "\n\n" + "\n".join(block)
    body = body.rstrip("\n") + "\n"
    # keep any non-owned rows the user added, after ours
    extra = [l for l in kept if l.strip() and not l.startswith("#")]
    if extra:
        body = body.rstrip("\n") + "\n" + "\n".join(extra) + "\n"

    if body == src:
        print(f"dsh-tui-ensure: {path}: profile layer already current")
        sys.exit(0)
    with open(path, "w", encoding="utf-8") as f:
        f.write(body)
    print(f"dsh-tui-ensure: {path}: wrote the profile layer (preset + code runtime)")

  '';

  ensureTui = pkgs.writeShellScript "dsh-tui-ensure" ''
    set -eu
    export PATH=/run/current-system/sw/bin:$PATH
    PROFILE_DIR="${homeDir}/.dsh/profiles/tui"
    [ -d "$PROFILE_DIR" ] || exit 0

    # pnpm cannot write nested node_modules through the @deepseek-ai store
    # symlink (read-only /nix/store), and a fresh `dsh plugin add` re-links the
    # tree: park the symlink for the duration of the pnpm operations and let the
    # relink below restore it.
    PROFILE_AI="$PROFILE_DIR/node_modules/@deepseek-ai"
    if [ -L "$PROFILE_AI" ]; then
      mv "$PROFILE_AI" "$PROFILE_AI.parked"
    fi

    PKG="$PROFILE_DIR/node_modules/@huiliyi37/dsh-tianshu-tui/package.json"
    VER=""
    if [ -f "$PKG" ]; then
      VER="$(jq -r '.version // "0.0.0"' "$PKG")"
    fi
    if [ -z "$VER" ] || [ "$(printf '%s\n%s\n' 0.1.2-rc.29 "$VER" | sort -V | head -1)" != "0.1.2-rc.29" ]; then
      echo "dsh-tui-ensure: installing dsh-tianshu-tui ^0.1.2-rc.29 (current: ''${VER:-missing}; 0.1.5 session API)..."
      ( cd "$PROFILE_DIR" && timeout 300 dsh plugin --profile tui add '@huiliyi37/dsh-tianshu-tui@^0.1.2-rc.29' -w ) \
        || echo "dsh-tui-ensure: install failed — will retry on next login" >&2
    fi

    # dsh-free-search: keyless search engines (ddg/bing/...), platform search,
    # `web_fetch`. The shipped `deepseek-official` provider answers with an empty
    # body from this region, so the profile rows below point the harness `web`
    # row at this plugin's `ddg` provider. 0.4.24 is the first release on the
    # 0.1.5 settings API; the relink further down repairs pnpm's peer copies.
    FS_PKG="$PROFILE_DIR/node_modules/dsh-free-search/package.json"
    FS_WANT=0.4.24
    # Registered means: the package is a profile dependency and its files are
    # there. A leftover directory from a half-finished pnpm run is deliberately
    # not "installed" — and note that `dsh plugin add` writes the dependency but
    # NOT `dsh.profile.bundles`, so the mount below is spelled out as explicit
    # rows instead of relying on the plugin's own bundle layer.
    fs_ok() {
      [ -f "$FS_PKG" ] || return 1
      [ "$(jq -r '.dependencies["dsh-free-search"] // ""' "$PROFILE_DIR/package.json")" != "" ] || return 1
      return 0
    }
    FS_HAVE=""
    if [ -f "$FS_PKG" ]; then
      FS_HAVE="$(jq -r '.version // ""' "$FS_PKG")"
    fi
    if ! fs_ok || [ "$(printf '%s\n%s\n' "$FS_WANT" "$FS_HAVE" | sort -V | head -1)" != "$FS_WANT" ]; then
      echo "dsh-tui-ensure: installing dsh-free-search ^$FS_WANT (keyless web search)..."
      ( cd "$PROFILE_DIR" && timeout 300 dsh plugin --profile tui add "dsh-free-search@^$FS_WANT" -w ) \
        || echo "dsh-tui-ensure: dsh-free-search install failed — will retry on next login" >&2
    fi

    # the parked symlink is superseded by the relink below
    rm -rf "$PROFILE_AI.parked"

    HARNESS_AI="${pkgs.neg.dsh}/lib/node_modules/@deepseek-ai"
    AI="$PROFILE_DIR/node_modules/@deepseek-ai"
    if [ -d "$HARNESS_AI" ] && { [ ! -L "$AI" ] || [ "$(readlink "$AI")" != "$HARNESS_AI" ]; }; then
      rm -rf "$AI"
      ln -s "$HARNESS_AI" "$AI"
      echo "dsh-tui-ensure: linked the profile @deepseek-ai to the harness tree"
    fi

    PATCH="$PROFILE_DIR/cordis.patch.yml"
    if [ -f "$PATCH" ]; then
      ROWS="$(mktemp)"
      printf '%s\n' ${lib.escapeShellArg tuiPluginRows} > "$ROWS"
      if fs_ok; then
        printf '%s\n' ${lib.escapeShellArg tuiSearchRows} >> "$ROWS"
      fi
      python3 ${presetPatch} "$PATCH" "$ROWS" || echo "dsh-tui-ensure: preset patch failed" >&2
      rm -f "$ROWS"
    fi

    # The neg preset (the TUI default, see below) mounts three repo-local
    # plugins that the web profile seeds through their own modules; without
    # copies here the preset aborts with "rows name plugins that cannot be
    # resolved". Copy-if-missing, the same contract those modules use, so local
    # tweaks survive.
    seed() {
      src="$1"; name="$2"; shift 2
      dir="$PROFILE_DIR/node_modules/$name"
      mkdir -p "$dir/lib"
      for f in "$@"; do
        [ -f "$dir/$f" ] || cp "$src/$f" "$dir/$f"
      done
    }
    # The user's host/agent plugins (see tuiPlugins): copy-if-missing, the same
    # contract their web-profile modules use, so edits in this repo re-apply
    # after deleting the profile copy.
    seed_pkg() {
      name="$1"; src="$2"
      [ -d "$src" ] || { echo "dsh-tui-ensure: $name missing in the repo" >&2; return 0; }
      [ -e "$PROFILE_DIR/node_modules/$name" ] && return 0
      mkdir -p "$PROFILE_DIR/node_modules/$name"
      cp -f "$src/package.json" "$PROFILE_DIR/node_modules/$name/package.json" 2>/dev/null || true
      cp -rf "$src/lib" "$PROFILE_DIR/node_modules/$name/lib"
      echo "dsh-tui-ensure: seeded $name"
    }
    # Path interpolation (not toString): it registers each plugin directory as a
    # build input, so the store copy exists even for plugins no other module
    # references (a toString-only string leaves the path outside the closure and
    # seed_pkg then reports it missing).
    ${lib.concatMapStrings (p: "seed_pkg ${p.name} ${p.path}\n") tuiPlugins}
    # The neg preset's own plugins (agent plane, referenced by the preset file).
    seed "${./dsh-advisor}" dsh-advisor package.json lib/index.js
    seed "${./dsh-category-skill-reminder}" dsh-category-skill-reminder package.json lib/index.js
    seed "${./dsh-ttsr}" dsh-ttsr package.json lib/index.js lib/rules.json

    # Theme: the repo copy is the source of truth (like the presets), but the
    # chosen theme in prefs.json is the user's — seed `custom:neg` only while
    # no theme is set, so `/theme` choices survive a rebuild.
    TUI_THEME_DIR="${homeDir}/.dsh-tui/themes"
    mkdir -p "$TUI_THEME_DIR"
    cp -f "${themeJson}" "$TUI_THEME_DIR/neg.json"
    TUI_PREFS="${homeDir}/.dsh-tui/prefs.json"
    if [ -f "$TUI_PREFS" ] && [ "$(jq -r '.theme // ""' "$TUI_PREFS")" = "" ]; then
      jq '.theme = "custom:neg"' "$TUI_PREFS" > "$TUI_PREFS.tmp" && mv "$TUI_PREFS.tmp" "$TUI_PREFS"
      echo "dsh-tui-ensure: seeded the neg theme (custom:neg)"
    fi

  '';
in
{
  # Apply on every nixos-rebuild (runs as root; bundles live under the user
  # home, so a rebuild after reinstall reproduces the Russian UI).
  system.activationScripts.dshTuiRu = lib.stringAfter [ "users" ] ''
    ${runPatch} || true
  '';

  # ...and on every login, so the patch survives plugin re-installs made
  # after the last rebuild.
  systemd.user.services.dsh-tui-ru = {
    enable = true;
    description = "dsh-tianshu-tui — apply Russian UI patch";
    wantedBy = [ "default.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = runPatch;
    };
  };

  # The profile caretaker runs as the user (it writes the profile's files) and
  # before the terminal UI starts; the Russian patch above only rewrites strings
  # and stays independent of it.
  system.activationScripts.dshTuiEnsure = lib.stringAfter [ "users" ] ''
    ${lib.getExe' pkgs.util-linux "runuser"} -u ${user} -- env HOME=${homeDir} ${ensureTui} || true
  '';

  systemd.user.services.dsh-tui-ensure = {
    enable = true;
    description = "dsh-tianshu-tui — keep the TUI profile on the installed harness";
    after = [ "network.target" ];
    wantedBy = [ "default.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = ensureTui;
    };
  };

  # The TUI self-updater (the self-update-park-harness fix in patch.mjs)
  # re-applies the Russian patch through this helper right after it installs a
  # bundle, before the host can restart into it — a raw npm release is
  # Chinese-only. Same script as the login/activation patch services.
  users.users.${user}.maid.file.home.".local/bin/dsh-tui-repatch" = {
    source = runPatch;
    executable = true;
  };
}
