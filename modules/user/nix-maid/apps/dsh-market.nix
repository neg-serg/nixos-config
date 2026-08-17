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

  # Idempotent patcher for the profile's pnpm-workspace.yaml:
  #  - minimumReleaseAgeExclude: dsh plugins publish frequently; exempt them
  #    from pnpm 11's default 24h release cooldown so plugin installs and
  #    updates apply immediately (pnpm otherwise silently keeps the old
  #    version and exits 0, which the plugin manager reports as "still vX
  #    after the update"). The list is rewritten wholesale (no duplicates, no
  #    versioned leftovers) — everything else keeps the default policy.
  #  - allowBuilds: explicit decisions for packages with install scripts
  #    (ssh2: JS fallback is fine without the native binding; cpu-features
  #    needs node-gyp/make which this host lacks; cloudflared downloads its
  #    official binary). Existing values — including pnpm's "set this to
  #    true or false" placeholders — are replaced in place.
  # Preserves any other keys pnpm or the user added.
  pnpmPatch = pkgs.writeText "dsh-market-pnpm-patch.py" ''
    import re
    import sys

    path = sys.argv[1]

    EXCLUDES = [
      "dsh-dream-skin",
      "@linxin666/*",
      "dsh-funnel",
      "dsh-pathlink",
      "dsh-file-upload",
      "@0xsline/dsh-spotlight",
      "dsh-plugin-vetting",
      "dsh-plugin-recall",
      "dsh-memento",
      "dsh-startup-guard",
      "dsh-free-search",
    ]
    ALLOW = {
      "cloudflared": "true",
      "cpu-features": "false",
      "ssh2": "true",
      "sharp": "true",
      "tesseract.js": "true",
      "gavel-review": "true",
    }

    with open(path) as f:
        lines = f.read().splitlines(keepends=True)

    def key_index(key):
        for i, line in enumerate(lines):
            if re.match(rf"^{re.escape(key)}:", line):
                return i
        return None

    changed = False

    # ---- minimumReleaseAgeExclude: rewrite the list block ----
    i = key_index("minimumReleaseAgeExclude")
    if i is None:
        lines.append("minimumReleaseAgeExclude:\n")
        i = len(lines) - 1
        changed = True
    j = i + 1
    while j < len(lines) and re.match(r"^\s*-\s", lines[j]):
        j += 1
    if lines[i + 1 : j] != [f'  - "{e}"\n' for e in EXCLUDES]:
        lines[i + 1 : j] = [f'  - "{e}"\n' for e in EXCLUDES]
        changed = True

    # ---- allowBuilds: set values in place ----
    i = key_index("allowBuilds")
    if i is None:
        lines.append("allowBuilds:\n")
        i = len(lines) - 1
        changed = True
    j = i + 1
    while j < len(lines) and re.match(r"^\s+\S+:\s*\S+", lines[j]):
        m = re.match(r"^\s+(\S+):\s*(\S+)\s*", lines[j])
        if m and m.group(1) in ALLOW and m.group(2) != ALLOW[m.group(1)]:
            lines[j] = f"  {m.group(1)}: {ALLOW[m.group(1)]}\n"
            changed = True
        j += 1
    known = {
        m.group(1)
        for line in lines[i + 1 : j]
        if (m := re.match(r"^\s+(\S+):\s*\S+\s*", line))
    }
    for k, v in ALLOW.items():
        if k not in known:
            lines.insert(j, f"  {k}: {v}\n")
            j += 1
            changed = True

    if changed:
        with open(path, "w") as f:
            f.writelines(lines)
        print(f"dsh-market: patched {path}")
    else:
        print(f"dsh-market: {path} already up to date")
  '';

  # The harness's own copy of the core @deepseek-ai package family. pnpm
  # (the profile's workspace sets nodeLinker: hoisted) hoists the transitive
  # @deepseek-ai deps of the third-party bundles into the profile's top-level
  # node_modules. The loader then resolves core rows (system-prompt, tools,
  # session, …) from THOSE copies while the preset machinery shipped inside
  # the harness (agent-presets, dsh-persona, dsh-agent-loop) resolves its
  # @deepseek-ai imports from the harness copy — two instances of dsh-scope
  # with two different `Symbol("dsh.scope")` tags. createScope (harness copy)
  # tags the standing mount's context, but SystemPrompt.section() reads the
  # tag through the profile copy and sees an unscoped context, so every preset
  # row lands in the GLOBAL prompt layer: "prompt section
  # \"deployment:persona\" already registered", every resume retries at 100%
  # CPU. Re-linking the profile's @deepseek-ai directory to the harness keeps
  # exactly one instance per package; re-applied after every pnpm sync.
  # Points at dsh-web-en — the same tree with the hardcoded Chinese UI copy
  # in the compiled web bundle rewritten to English (packages/dsh/web-ui-en).
  # dsh-web-en mirrors the harness node_modules layout (scope + hoisted deps
  # under node_modules/), so the profile's @deepseek-ai symlink must target
  # its nested scope dir to keep intra-scope and hoisted imports resolvable.
  dshAiStore = "${pkgs.neg.dsh-web-en}/node_modules/@deepseek-ai";

  # Idempotent: keep the profile's declarative plugin set installed (release
  # cooldown exemptions + build-script allowlist in pnpm-workspace.yaml),
  # re-link the profile's @deepseek-ai copies to the harness (see dshAiStore),
  # apply the cordis.patch.yml overlays (disabled UI panels, terminal-ui,
  # gui-tweaks, osm, dsh-prompt, web-runtime LAN pairing), and restart the
  # running web UI once on a fresh install so new plugins activate.
  # Note: the dshmarket plugin (Settings → Plugin Market) was removed on
  # request; plugins are managed declaratively here instead.
  ensureMarket = pkgs.writeShellScript "dsh-market-ensure" ''
            set -eu
            export PATH=/run/current-system/sw/bin:$PATH
            PROFILE_DIR="${homeDir}/.dsh/profiles/web"
            mkdir -p "$PROFILE_DIR"

            # Supply-chain policy first: without the cooldown exemptions, fresh
            # dsh plugin releases are silently held back by pnpm 11.
            python3 ${pnpmPatch} "$PROFILE_DIR/pnpm-workspace.yaml" \
              || echo "dsh-market: pnpm policy patch failed" >&2

            # pnpm cannot write nested node_modules through the @deepseek-ai
            # store symlink (read-only /nix/store, see dshAiStore below), and
            # any fresh `dsh plugin add` re-links the tree — park the symlink
            # for the duration of the pnpm operations below and restore it
            # after. The relink block further down then no-ops (or re-pins a
            # stale target).
            PROFILE_AI="$PROFILE_DIR/node_modules/@deepseek-ai"
            if [ -L "$PROFILE_AI" ]; then
              mv "$PROFILE_AI" "$PROFILE_AI.parked"
            fi

            installed=0

            # Declarative plugin set — ensure-if-missing pattern. `-w` is
            # required: the profile is a pnpm workspace root (packages: ['.']),
            # and pnpm 11 refuses `add` from the root without it. allowBuilds
            # entries for native deps (sharp/tesseract.js/gavel-review) live in
            # pnpmPatch above, so fresh installs don't trip
            # ERR_PNPM_IGNORED_BUILDS. Pairs are "package-name:install-spec" so
            # scoped names (@0xsline/...) stay unambiguous.
            for entry in \
              "dsh-funnel:dsh-funnel" \
              "dsh-pathlink:dsh-pathlink" \
              "dsh-file-upload:dsh-file-upload" \
              "@0xsline/dsh-spotlight:@0xsline/dsh-spotlight" \
              "dsh-plugin-vetting:dsh-plugin-vetting@^0.5.6" \
              "dsh-plugin-recall:dsh-plugin-recall" \
              "dsh-memento:dsh-memento" \
              "dsh-startup-guard:dsh-startup-guard" \
              "dsh-free-search:dsh-free-search" \
              "dsh-status-rotator:github:01Virex/dsh-status-rotator"; do
              name="''${entry%%:*}"
              spec="''${entry#*:}"
              if ! grep -q "\"$name\"" "$PROFILE_DIR/package.json" 2>/dev/null; then
                echo "dsh-market: installing $name into the web profile..."
                if dsh plugin --profile web add "$spec" -w; then
                  installed=1
                else
                  echo "dsh-market: install of $name failed — will retry on next login" >&2
                fi
              fi
            done

            # gavel-review (JohnXu22786/adversarial-review) is not on npm and
            # ships no committed build — bootstrap a local clone + build, then
            # link it like any other plugin. The clone at ~/src/gavel-review is
            # the source of truth; only built when missing.
            if ! grep -q '"gavel-review"' "$PROFILE_DIR/package.json" 2>/dev/null; then
              GAVEL_DIR="$HOME/src/gavel-review"
              if [ ! -d "$GAVEL_DIR/.git" ]; then
                git clone --depth 1 https://github.com/JohnXu22786/adversarial-review "$GAVEL_DIR" 2>/dev/null \
                  || echo "dsh-market: gavel-review clone failed" >&2
              fi
              if [ -d "$GAVEL_DIR" ] && [ ! -f "$GAVEL_DIR/lib/index.js" ]; then
                (cd "$GAVEL_DIR" && npm install --no-audit --no-fund && npm run build) >/dev/null 2>&1 \
                  || echo "dsh-market: gavel-review build failed" >&2
              fi
              if [ -f "$GAVEL_DIR/lib/index.js" ]; then
                dsh plugin --profile web add "$GAVEL_DIR" -w && installed=1 \
                  || echo "dsh-market: gavel-review install failed" >&2
              fi
            fi

            # dsh-status-rotator: seed the user-editable phrase config next to
            # the package (the node half serves config.example.json as a
            # fallback when this file is absent).
            SR="$PROFILE_DIR/node_modules/dsh-status-rotator"
            if [ -d "$SR" ] && [ ! -f "$SR/config.json" ]; then
              cp "$SR/config.example.json" "$SR/config.json"
            fi

            # Keep the turn-status gradient and phrase set in line with the
            # neg look (muted blues/teals/purples from
            # ~/.config/zsh/neg.omp.json, Russian status phrases) —
            # reproducible across plugin reinstalls. Only stock values are
            # replaced, so manual edits in config.json survive.
            python3 - "$SR/config.json" "$SR/config.example.json" <<'PY'
    import json, sys

    RAINBOW = ["#ff5f6d", "#ffc371", "#ffdd55", "#7dff7d", "#5fd4ff", "#a78bfa", "#ff8adb"]
    PALETTE = ["#005faf", "#367CB0", "#6C7E96", "#287373", "#5E468C", "#914E89"]

    STOCK_EN_FIRST = {
        "thinking": "Distilling Fable 5…",
        "running": "Playing Wordle against itself…",
        "long": "Thinking for 22 hours without answering…",
    }
    RU_PHRASES = {
        "thinking": [
            "Думаю…",
            "Собираю контекст…",
            "Читаю задачу…",
            "Строю план…",
            "Погружаюсь…",
            "Разбираю вопрос…",
            "Ищу подход…",
            "Обдумываю…",
            "Разогреваю нейроны…",
            "Готовлю ответ…",
            "Просыпаюсь…",
            "Синхронизирую мысли…",
        ],
        "running": [
            "Всё ещё думаю…",
            "Копаю глубже…",
            "Перебираю варианты…",
            "Пишу код…",
            "Проверяю гипотезы…",
            "Листаю документацию…",
            "Собираю выводы…",
            "Довожу до ума…",
            "Уточняю детали…",
            "Работаю над этим…",
            "Шлифую…",
            "Не отвлекаюсь…",
        ],
        "long": [
            "Это надолго…",
            "Заварил чай…",
            "Глубокое погружение…",
            "Всё под контролем…",
            "Ещё чуть-чуть…",
            "Терпение…",
            "Думаю о вечном…",
            "Не сдаюсь…",
            "Полный вперёд…",
        ],
    }

    def patch(path):
        try:
            with open(path, encoding="utf-8") as f:
                cfg = json.load(f)
        except (OSError, ValueError):
            return
        changed = False
        g = cfg.get("config", {}).get("gradient")
        if isinstance(g, dict) and g.get("colors") == RAINBOW:
            g["colors"] = PALETTE
            g["speed"] = 6
            changed = True
        en = cfg.get("phrases", {}).get("en")
        if isinstance(en, dict):
            for phase, first in STOCK_EN_FIRST.items():
                lst = en.get(phase)
                if isinstance(lst, list) and lst and lst[0] == first:
                    en[phase] = RU_PHRASES[phase]
                    changed = True
        # The zh phrase block is stock Chinese ("正在蒸馏Fable 5…" etc.);
        # replace it with the Russian phrases so the status line carries no
        # Chinese characters in any locale.
        zh = cfg.get("phrases", {}).get("zh")
        if isinstance(zh, dict) and any(
            isinstance(zh.get(k), list) and zh[k] and "\u4e00" <= zh[k][0][0] <= "\u9fff"
            for k in ("thinking", "running", "long")
        ):
            cfg["phrases"]["zh"] = RU_PHRASES
            changed = True
        if changed:
            with open(path, "w", encoding="utf-8") as f:
                json.dump(cfg, f, ensure_ascii=False, indent=4)
                f.write("\n")

    for p in sys.argv[1:]:
        patch(p)
    PY

            # Restore the parked @deepseek-ai symlink (discard whatever pnpm
            # materialized there while it was parked; the relink block below
            # re-pins the profile to the harness store when needed).
            if [ -e "$PROFILE_AI.parked" ]; then
              rm -rf "$PROFILE_AI"
              mv "$PROFILE_AI.parked" "$PROFILE_AI"
            fi

            # pnpm install may rewrite pnpm-workspace.yaml; re-apply the policy.
            python3 ${pnpmPatch} "$PROFILE_DIR/pnpm-workspace.yaml" \
              || echo "dsh-market: pnpm policy re-patch failed" >&2

            # Re-link the profile's @deepseek-ai to the harness's own copies so
            # core rows and the preset machinery share one module instance per
            # package (see dshAiStore). Do this AFTER any pnpm operation.
            PROFILE_AI="$PROFILE_DIR/node_modules/@deepseek-ai"
            # Relink when pnpm recreated the dir (not a symlink) OR when the
            # symlink points at a stale store path (e.g. a pre-patch build) —
            # the profile must resolve the harness's own copies so core rows
            # and the preset machinery share one module instance per package.
            if [ -d "$PROFILE_AI" ] && { [ ! -L "$PROFILE_AI" ] || [ "$(readlink "$PROFILE_AI")" != "${dshAiStore}" ]; }; then
              rm -rf "$PROFILE_AI"
              ln -s "${dshAiStore}" "$PROFILE_AI"
              echo "dsh-market: re-linked profile @deepseek-ai to the harness store"
            fi

            PATCH="$PROFILE_DIR/cordis.patch.yml"

            # UI panels the user disabled in the web GUI (right-side
            # Explorer/Preview/Files, Task Board, pet widget, skin center, dream
            # skin, better sidebar, SSH panel). Kept declarative here so a
            # rebuild or login re-asserts them; the rows are appended
            # idempotently when missing.
            if ! grep -q 'ui-dsh-aionui-panel' "$PATCH" 2>/dev/null; then
              cat >> "$PATCH" <<'YAML'

    # Disabled UI panels — see dsh-market.nix (dsh web GUI declutter).
    - id: ui-dsh-aionui-panel
      disabled: true
    - id: ui-task-board
      disabled: true
    - id: pet
      disabled: true
    - id: ui-skin-center
      disabled: true
    - id: dream-skin
      disabled: true
    - id: better-sidebar
      disabled: true
    - id: ssh
      disabled: true
    - id: ui-git-graph
      disabled: true
    YAML
            fi

            # dsh-terminal-ui: wider chat column, Iosevka fonts, terminal-ish
            # typography. Canonical source is the dsh-web-ui fork checkout
            # (packages/dsh-terminal-ui): symlink into the profile so source
            # edits apply on the next page refresh. If the fork checkout is
            # missing the plugin is skipped with a warning (fresh machine
            # before `git clone`).
            TUI="$PROFILE_DIR/node_modules/dsh-terminal-ui"
            TUI_FORK="${homeDir}/src/1st-level/@projects/dsh-web-ui/packages/dsh-terminal-ui"
            if [ -d "$TUI_FORK" ]; then
              # Replace a plain copy (from before the fork migration) with the symlink.
              if [ ! -L "$TUI" ]; then
                rm -rf -- "$TUI" 2>/dev/null || true
              fi
              ln -sfn "$TUI_FORK" "$TUI"
            else
              echo "dsh-terminal-ui: fork checkout missing at $TUI_FORK — plugin not installed" >&2
            fi

            # Ensure the profile patch carries the terminal-ui row (insert form).
            if ! grep -q 'terminal-ui' "$PATCH" 2>/dev/null; then
              cat >> "$PATCH" <<'YAML'

    # dsh-terminal-ui - wider chat column, Iosevka, terminal-ish look
    # (package lives in node_modules/dsh-terminal-ui, see dsh-market.nix).
    - insert:
        - id: terminal-ui
          name: dsh-terminal-ui
    YAML
            fi

            # dsh-preview: serves image files from the user's workspaces, home
            # and tmp dirs to the browser at /dsh-preview/<path>. The markdown
            # renderer rewrites non-URL image sources to this route, so
            # `![name](path)` previews local images in assistant messages and
            # thoughts. Image content types only; paths must resolve inside an
            # allowed root (workspace registry + home + tmp).
            PREVIEW="$PROFILE_DIR/node_modules/dsh-preview"
            # Canonical source is the dsh-web-ui fork checkout
            # (packages/dsh-preview): symlink into the profile, same pattern as
            # dsh-terminal-ui, so source edits apply on the next page refresh.
            # If the fork checkout is missing the plugin is skipped with a
            # warning (fresh machine before `git clone`).
            PREVIEW_FORK="${homeDir}/src/1st-level/@projects/dsh-web-ui/packages/dsh-preview"
            if [ -d "$PREVIEW_FORK" ]; then
              # Replace a plain copy (from before the fork migration) with the symlink.
              if [ ! -L "$PREVIEW" ]; then
                rm -rf -- "$PREVIEW" 2>/dev/null || true
              fi
              ln -sfn "$PREVIEW_FORK" "$PREVIEW"
            else
              echo "dsh-preview: fork checkout missing at $PREVIEW_FORK — plugin not installed" >&2
            fi

# Ensure the profile patch carries the dsh-preview row (insert form).
            if ! grep -q 'dsh-preview' "$PATCH" 2>/dev/null; then
              cat >> "$PATCH" <<'YAML'

    # dsh-preview - serve workspace image previews for assistant markdown
    # (package lives in node_modules/dsh-preview, see dsh-market.nix).
    - insert:
        - id: dsh-preview
          name: dsh-preview
    YAML
            fi

            # LAN phone pairing (dsh-remote-web-ui): dsh itself stays bound to
            # loopback; a narrow LAN socket (systemd-socket-proxyd, see dsh.nix)
            # forwards 192.168.2.87:3080 → 127.0.0.1:3080 so a phone on the
            # local network can pair. The /api trust fence only accepts
            # loopback + the derived LAN literals of an all-interfaces bind —
            # here the bind stays 127.0.0.1, so the LAN authority the phone
            # uses must be added to trustedHosts explicitly.
            if ! grep -q 'web-runtime' "$PATCH" 2>/dev/null; then
              cat >> "$PATCH" <<'YAML'

    # LAN phone pairing - accept the LAN authority the dsh-lan-proxy socket
    # serves (192.168.2.87:3080) in the /api browser-trust fence, while dsh
    # itself keeps binding 127.0.0.1. The phone panel URL comes from the
    # remote-web-ui `publicBaseUrl` setting (settings.yaml). The !!js value
    # must stay QUOTED: an unquoted array literal makes the YAML parser read
    # it as a flow collection and dsh fails to parse the overlay.
    - id: web-runtime
      config:
        printUrl: true
        surfaceContext: true
        trustedHosts: !!js "[...(ctx.webStartup?.trustedHosts ?? []), '192.168.2.87']"
    YAML
            fi

            if [ "$installed" = 1 ]; then
              export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
              systemctl --user restart dsh.service 2>/dev/null || true
            fi
  '';
in
{
  # Declarative dsh web profile management: ensures the plugin set,
  # pnpm supply-chain policy (release-cooldown exemptions for
  # fast-publishing dsh plugins, build-script allowlist) and the
  # cordis.patch.yml overlays stay in place across rebuilds and manual
  # plugin churn. Runs on every rebuild (as the user, so profile files stay
  # user-owned) and on every login — same pattern as dsh-tui-ru.
  system.activationScripts.dshMarketEnsure = lib.stringAfter [ "users" ] ''
    ${lib.getExe' pkgs.util-linux "runuser"} -u ${user} -- env HOME=${homeDir} ${ensureMarket} || true
  '';

  systemd.user.services.dsh-market-ensure = {
    enable = true;
    description = "dsh-market — ensure declarative plugin set + pnpm policy in the dsh web profile";
    after = [ "network.target" ];
    before = [ "dsh.service" ];
    wantedBy = [ "default.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = ensureMarket;
    };
  };
}
