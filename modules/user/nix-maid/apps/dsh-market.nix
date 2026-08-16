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
// dsh-terminal-ui host half: nothing to do on the server side.
const inject = [];
function apply(_ctx) {}
export { apply, inject };
JS
          cat > "$TUI/lib/client.js" <<'JS'
// dsh-terminal-ui client half - wider chat column, Iosevka fonts, terminal-ish
// typography. Injects one <style> element for the page lifetime; removed when
// the plugin unmounts.
window.__ModuleLoader__.load({
  id: "dsh-terminal-ui",
  factory: (require) => {
    const inject = [];

    // NOTE: `.wSkVaW_root` is the conversation-root class from
    // @deepseek-ai/dsh-client-ui-conversation (CSS module hash). It is stable
    // for a pinned dsh release; if the class stops matching after an upgrade,
    // re-derive it from the served client bundle (grep for
    // `--dsh-chat-content-width:748px`).
    const CSS = `
:root {
  --dsw-font-family: "Iosevka", "Iosevka Medium", ui-monospace, "SF Mono", Menlo, Consolas, monospace;
  --ds-font-family-code: "Iosevka", "Iosevka Medium", ui-monospace, "SF Mono", Menlo, Consolas, monospace;
}
.wSkVaW_root {
  --dsh-chat-content-width: min(1200px, calc(100vw - 240px));
  --dsh-composer-card-max-width: calc(var(--dsh-chat-content-width) + 32px);
}
body {
  --dsw-font-markdown-base: 400 15px/24px var(--dsw-font-family);
  --dsw-font-markdown-base-font-size: 15px;
  --dsw-font-markdown-base-line-height: 24px;
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
