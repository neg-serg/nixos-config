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
  #    instance per package, exactly as dsh-market.nix does for the web profile.
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
  # remote-web-ui, web-ui-settings, gui-tweaks, pet) stay out.
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
    # dsh-memory-extractor stays web-only: it injects the `memory` service,
    # which this profile does not provide (the web profile gets it from the
    # memento plugin).
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
  ];

  # Loader rows for the plugins above, mirroring the web profile's patch layer
  # (the row id is the package name; only memory-extractor carries config, which
  # is appended as its own row below).
  tuiPluginRows = lib.concatMapStrings (name: ''
    - insert:
        - id: ${name}
          name: ${name}
  '') (map (p: p.name) (lib.filter (p: p.name != "dsh-memory-extractor") tuiPlugins));

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

    PKG="$PROFILE_DIR/node_modules/@huiliyi37/dsh-tianshu-tui/package.json"
    if [ -f "$PKG" ]; then
      VER="$(jq -r '.version // "0.0.0"' "$PKG")"
      if [ "$(printf '%s\n%s\n' 0.1.2-rc.29 "$VER" | sort -V | head -1)" != "0.1.2-rc.29" ]; then
        echo "dsh-tui-ensure: upgrading dsh-tianshu-tui $VER -> ^0.1.2-rc.29 (0.1.5 session API)..."
        ( cd "$PROFILE_DIR" && dsh plugin --profile tui add '@huiliyi37/dsh-tianshu-tui@^0.1.2-rc.29' -w ) \
          || echo "dsh-tui-ensure: upgrade failed — will retry on next login" >&2
      fi
    fi

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
    ${lib.concatMapStrings (p: "seed_pkg " + p.name + " " + toString p.path + "\n") tuiPlugins}
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
}
