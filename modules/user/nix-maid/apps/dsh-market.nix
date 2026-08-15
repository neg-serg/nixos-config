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

  # Idempotent: install the dshmarket plugin into the web profile when absent,
  # keep the profile's pnpm supply-chain policy sane (release cooldown
  # exemptions + build-script allowlist), pin `allowRestart: false` in the
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
