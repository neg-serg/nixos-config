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
  #    from pnpm 11's default 24h release cooldown so dshmarket installs and
  #    updates apply immediately (pnpm otherwise silently keeps the old
  #    version and exits 0, which dshmarket reports as "still vX after the
  #    update"). The list is rewritten wholesale (no duplicates, no
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

    EXCLUDES = ["dshmarket", "dsh-dream-skin", "@linxin666/*"]
    ALLOW = {"cloudflared": "true", "cpu-features": "false", "ssh2": "true"}

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
  dshAiStore = "${pkgs.neg.dsh}/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai";

  # Idempotent: install the dshmarket plugin into the web profile when absent,
  # keep the profile's pnpm supply-chain policy sane (release cooldown
  # exemptions + build-script allowlist), re-link the profile's @deepseek-ai
  # copies to the harness (see dshAiStore), pin `allowRestart: false` in the
  # profile's cordis.patch.yml (dsh web runs under systemd, so the market's
  # detached-restart button must stay off — the supervisor owns restarts),
  # and restart the running web UI once on a fresh install so Settings →
  # Plugin Market appears without manual intervention.
  ensureMarket = pkgs.writeShellScript "dsh-market-ensure" ''
        set -eu
        export PATH=/run/current-system/sw/bin:$PATH
        PROFILE_DIR="${homeDir}/.dsh/profiles/web"
        mkdir -p "$PROFILE_DIR"

        # Supply-chain policy first: without the cooldown exemptions, fresh
        # dsh plugin releases are silently held back by pnpm 11.
        python3 ${pnpmPatch} "$PROFILE_DIR/pnpm-workspace.yaml" \
          || echo "dsh-market: pnpm policy patch failed" >&2

        installed=0
        if ! grep -q '"dshmarket"' "$PROFILE_DIR/package.json" 2>/dev/null; then
          echo "dsh-market: installing dshmarket into the web profile..."
          dsh plugin --profile web add dshmarket \
            || { echo "dsh-market: install failed (offline? pnpm?) — will retry on next login" >&2; exit 0; }
          installed=1
        fi

        # pnpm install may rewrite pnpm-workspace.yaml; re-apply the policy.
        python3 ${pnpmPatch} "$PROFILE_DIR/pnpm-workspace.yaml" \
          || echo "dsh-market: pnpm policy re-patch failed" >&2

        # Re-link the profile's @deepseek-ai to the harness's own copies so
        # core rows and the preset machinery share one module instance per
        # package (see dshAiStore). Do this AFTER any pnpm operation.
        PROFILE_AI="$PROFILE_DIR/node_modules/@deepseek-ai"
        if [ -d "$PROFILE_AI" ] && [ ! -L "$PROFILE_AI" ]; then
          rm -rf "$PROFILE_AI"
          ln -s "${dshAiStore}" "$PROFILE_AI"
          echo "dsh-market: re-linked profile @deepseek-ai to the harness store"
        fi

        PATCH="$PROFILE_DIR/cordis.patch.yml"
        if ! grep -q 'allowRestart' "$PATCH" 2>/dev/null; then
          cat > "$PATCH" <<'YAML'
# Managed by NixOS (modules/user/nix-maid/apps/dsh-market.nix) — do not edit.
# dsh web runs under systemd, so the market's one-click restart is disabled;
# the supervisor owns restarts.
- id: dsh-market
  config:
    allowRestart: false
YAML
        fi

        # UI panels the user disabled in the web GUI (right-side
        # Explorer/Preview/Files, Task Board, pet widget, skin center, dream
        # skin, better sidebar). Kept declarative here so a rebuild or login
        # re-asserts them; the rows are appended idempotently when missing.
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
YAML
        fi

        # dsh-terminal-ui: wider chat column, Iosevka fonts, terminal-ish
        # typography. The package is a plain directory in the profile's
        # node_modules (pnpm is intentionally not used — the @deepseek-ai
        # store symlink makes pnpm writes fail with EROFS, see dshAiStore).
        # Files are written only when missing, so local tweaks to client.js
        # survive; the profile patch row is ensured the same way.
        TUI="$PROFILE_DIR/node_modules/dsh-terminal-ui"
        if [ ! -f "$TUI/package.json" ] || [ ! -f "$TUI/lib/client.js" ]; then
          mkdir -p "$TUI/lib"
          cat > "$TUI/package.json" <<'JSON'
{
  "name": "dsh-terminal-ui",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "main": "lib/index.js",
  "exports": {
    ".": "./lib/index.js",
    "./client": "./lib/client.js",
    "./package.json": "./package.json"
  },
  "dsh": {
    "client": {
      "inject": [],
      "platform": "web"
    }
  }
}
JSON
          cat > "$TUI/lib/index.js" <<'JS'
// dsh-terminal-ui host half: serves the desktop wallpaper to the browser at
// /terminal-ui/wallpaper so the client theme can use it as a background.
// The served file follows the wl wallpaper daemon's current pick
// (~/.cache/quickshell-wallpaper-path), falling back to a fixed path.
import { readFileSync, existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const inject = ["webServer"];

const WALLPAPER_HINT = join(homedir(), ".cache/quickshell-wallpaper-path");
const FALLBACK = "/home/neg/pic/wl/wallhaven-jek6kq.jpg";

function resolveWallpaper() {
  try {
    const p = readFileSync(WALLPAPER_HINT, "utf8").trim();
    if (p && existsSync(p)) return p;
  } catch {
    /* hint file missing or unreadable - fall through */
  }
  return existsSync(FALLBACK) ? FALLBACK : null;
}

function contentTypeOf(path) {
  if (/\.png$/i.test(path)) return "image/png";
  if (/\.webp$/i.test(path)) return "image/webp";
  if (/\.gif$/i.test(path)) return "image/gif";
  return "image/jpeg";
}

function apply(ctx) {
  ctx.effect(() =>
    ctx.webServer.register({
      kind: "exact",
      path: "/terminal-ui/wallpaper",
      handler(_req, res) {
        try {
          const path = resolveWallpaper();
          if (path === null) {
            res.writeHead(404, { "content-type": "text/plain; charset=utf-8" });
            res.end("no wallpaper configured");
            return;
          }
          const body = readFileSync(path);
          res.writeHead(200, {
            "content-type": contentTypeOf(path),
            "content-length": body.length,
            "cache-control": "public, max-age=3600",
          });
          res.end(body);
        } catch (error) {
          res.writeHead(500, { "content-type": "text/plain; charset=utf-8" });
          res.end(String(error));
        }
      },
    }),
  );
}

export { apply, inject };
JS
          cat > "$TUI/lib/client.js" <<'JS'
// dsh-terminal-ui client half - neg theme (dark navy + deep blue accent),
// translucent glass surfaces over the desktop wallpaper, Iosevka fonts,
// wider chat column. Injects one <style> element for the page lifetime;
// removed when the plugin unmounts.
window.__ModuleLoader__.load({
  id: "dsh-terminal-ui",
  factory: (require) => {
    const inject = [];

    // Theme tokens are declared on `body` / `body[data-ds-dark-theme]`
    // (see dsh-client-ui-theme). Re-declaring them on the same selectors in
    // a later stylesheet wins the cascade; rgba values plus the wallpaper
    // layer give the translucent glass look. Both light and dark slots get
    // the neg palette, so the GUI keeps the neg look in either mode.
    // `.wSkVaW_root` is the conversation-root class from
    // @deepseek-ai/dsh-client-ui-conversation (CSS module hash) - stable for
    // a pinned dsh release; re-derive from the served client bundle if it
    // stops matching after an upgrade (grep for `--dsh-chat-content-width`).
    const CSS = `
/* -- wallpaper + base -- */
html {
  background: #040f1c;
}
body {
  background: transparent;
}
body::before {
  content: "";
  position: fixed;
  inset: 0;
  z-index: -1;
  background: url("/terminal-ui/wallpaper") center / cover no-repeat;
}

/* -- neg palette (translucent surfaces) -- */
body,
body[data-ds-dark-theme] {
  --dsw-alias-bg-base: rgba(4, 15, 28, 0.74);
  --dsw-alias-bg-layer-1: rgba(12, 28, 48, 0.68);
  --dsw-alias-bg-layer-2: rgba(16, 35, 58, 0.62);
  --dsw-alias-bg-layer-3: rgba(22, 45, 72, 0.56);
  --dsw-alias-bg-overlay: rgba(12, 28, 48, 0.88);
  --dsw-alias-border-l1: rgba(43, 68, 98, 0.5);
  --dsw-alias-border-l2: rgba(28, 51, 78, 0.75);
  --dsw-alias-border-l3: rgba(43, 68, 98, 0.6);
  --dsw-alias-label-primary: #a4b3c6;
  --dsw-alias-label-secondary: #6d839e;
  --dsw-alias-label-tertiary: #5c7391;
  --dsw-alias-brand-primary: #367bbf;
  --dsw-alias-brand-text: #d1e5ff;
  --dsw-alias-button-primary-fill: #005faf;
  --dsw-alias-button-primary-hover: #367cb0;
  --dsw-alias-button-primary-dimmed: rgba(16, 35, 58, 0.9);
  --dsw-alias-button-elevated-fill: rgba(12, 28, 48, 0.8);
  --dsw-alias-button-floating-fill: rgba(12, 28, 48, 0.8);
  --dsw-alias-button-floating-hover: rgba(16, 35, 58, 0.85);
  --dsw-alias-button-info-fill: #005faf;
  --dsw-alias-button-info-hover: #367cb0;
  --dsw-alias-state-success-primary: #37b393;
  --dsw-alias-state-error-primary: #d86f96;
  --dsw-alias-state-warn-primary: #c8a8ef;
  --dsw-alias-state-business-primary: #367bbf;
  --dsw-specific-sidebar-fill: rgba(4, 15, 28, 0.55);
  --dsw-specific-sidebar-nav-item-active: rgba(16, 35, 58, 0.85);
  --dsw-specific-sidebar-nav-item-hover: rgba(28, 51, 78, 0.7);
  --dsw-specific-bubble: rgba(12, 28, 48, 0.6);
  --dsw-specific-bubble-highlight: rgba(16, 35, 58, 0.65);
  --dsw-specific-input-major: rgba(12, 28, 48, 0.7);
  --dsw-specific-selector: rgba(16, 35, 58, 0.7);
  --dsw-specific-menu: rgba(12, 28, 48, 0.9);
  --dsw-alias-markdown-code-block: rgba(0, 0, 0, 0.35);
  --dsw-alias-markdown-inline-code: rgba(16, 35, 58, 0.7);
  --dsw-alias-scrollbar-bg-l1: rgba(12, 28, 48, 0.6);
  --dsw-alias-scrollbar-bg-l2: rgba(16, 35, 58, 0.6);
  --dsw-alias-scrollbar-hover-l1: rgba(28, 51, 78, 0.9);
  --dsw-alias-scrollbar-hover-l2: rgba(43, 68, 98, 0.9);
  --dsw-alias-interactive-bg-hover: rgba(255, 255, 255, 0.06);
  --dsw-alias-interactive-bg-active: rgba(255, 255, 255, 0.1);
}

/* -- glass blur on the columns (data-pane stamped by dsh-web-ui-all) -- */
[data-pane="conversation"],
[data-pane="sidebar"],
[class*="sidebarCol"],
[class*="centerCol"],
[class*="detailsCol"] {
  backdrop-filter: blur(14px) saturate(1.15);
  -webkit-backdrop-filter: blur(14px) saturate(1.15);
}

/* -- fonts + wider chat -- */
:root {
  --dsw-font-family: "Iosevka", "Iosevka Medium", ui-monospace, "SF Mono", Menlo, Consolas, monospace;
  --ds-font-family-code: "Iosevka", "Iosevka Medium", ui-monospace, "SF Mono", Menlo, Consolas, monospace;
}
.wSkVaW_root {
  --dsh-chat-content-width: min(1200px, calc(100vw - 240px));
  --dsh-composer-card-max-width: calc(var(--dsh-chat-content-width) + 32px);
}
body {
  --dsw-font-markdown-base: 400 14px/22px var(--dsw-font-family);
  --dsw-font-markdown-base-font-size: 14px;
  --dsw-font-markdown-base-line-height: 22px;
}

/* -- terminal pass: flat, dense, squared -- */

/* message flow: denser, like terminal scrollback */
.Md3f7G_column {
  gap: 10px;
}

/* all message rows: full-width flat lines (no chat bubbles) */
.gdEzaW_userRow {
  align-items: stretch;
}
.gdEzaW_bubble {
  background: transparent;
  border: none;
  border-radius: 0;
  padding: 2px 0;
  max-width: 100%;
  font-size: 14px;
  line-height: 22px;
}
.gdEzaW_bubble::before {
  content: "❯ ";
  color: var(--dsw-alias-state-success-primary);
  font-weight: 600;
}

/* code blocks: terminal panes with a header strip */
.ydkMvW_code {
  position: relative;
  border-radius: 4px;
  border-left: 3px solid var(--dsw-alias-brand-primary);
  padding: 30px 14px 12px;
  font-size: 12px;
  line-height: 19px;
}
.ydkMvW_code::before {
  content: "❯";
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  height: 22px;
  padding: 2px 10px;
  box-sizing: border-box;
  background: rgba(0, 0, 0, 0.35);
  border-bottom: 1px solid var(--dsw-alias-border-l1);
  color: var(--dsw-alias-state-success-primary);
  font-size: 12px;
  line-height: 18px;
}

/* tool call rows: flat */
.Md3f7G_callRow {
  border-radius: 2px;
}

/* composer seat: terminal input divider */
[data-composer-seat] {
  border-top: 1px solid rgba(54, 123, 191, 0.4);
}

/* terminal input: green bar caret (blinks natively), 14px.
   Note: `caret-shape: block` was tried but Chromium renders it brokenly on
   this auto-growing textarea (stray green blocks at wrong positions), so we
   keep the standard bar caret and only tint it green. */
.uV2eYG_input {
  font-size: 14px;
  caret-shape: auto;
  caret-color: #37b393;
}

/* terminal status readouts: turn status + dock band under the composer */
.Md3f7G_turnStatus {
  font-family: var(--ds-font-family-code);
  font-size: 12px;
  color: var(--dsw-alias-state-success-primary);
}
._7rgC5q_anchorDock {
  background: rgba(4, 15, 28, 0.85);
  border-top: 1px solid var(--dsw-alias-border-l1);
  font-family: var(--ds-font-family-code);
  font-size: 12px;
  color: var(--dsw-alias-label-secondary);
  padding: 2px 12px;
}

/* terminal-style selection */
::selection {
  background: rgba(54, 123, 191, 0.45);
  color: #eaf3ff;
}
`;

    function apply(ctx) {
      ctx.effect(() => {
        const style = document.createElement("style");
        style.setAttribute("data-dsh-terminal-ui", "");
        style.textContent = CSS;
        document.head.appendChild(style);
        return () => {
          style.remove();
        };
      });
    }

    return { apply, inject };
  },
});
JS
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

        if [ "$installed" = 1 ]; then
          export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
          systemctl --user restart dsh.service 2>/dev/null || true
        fi
  '';
in
{
  # Plugin market for dsh web: Settings → Plugin Market (browse the
  # awesome-dsh-plugin catalog, one-click install/update/uninstall).
  # Also owns the profile's pnpm supply-chain policy (release-cooldown
  # exemptions for fast-publishing dsh plugins, build-script allowlist).
  # Runs on every rebuild (as the user, so profile files stay user-owned)
  # and on every login (recovery after manual plugin churn) — same pattern
  # as dsh-tui-ru.
  system.activationScripts.dshMarketEnsure = lib.stringAfter [ "users" ] ''
    ${lib.getExe' pkgs.util-linux "runuser"} -u ${user} -- env HOME=${homeDir} ${ensureMarket} || true
  '';

  systemd.user.services.dsh-market-ensure = {
    enable = true;
    description = "dshmarket — ensure plugin market + pnpm policy in the dsh web profile";
    after = [ "network.target" ];
    before = [ "dsh.service" ];
    wantedBy = [ "default.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = ensureMarket;
    };
  };
}
