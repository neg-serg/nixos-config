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

  # Idempotent: install the dshmarket plugin into the web profile when absent,
  # pin `allowRestart: false` in the profile's cordis.patch.yml (dsh web runs
  # under systemd, so the market's detached-restart button must stay off — the
  # supervisor owns restarts), and restart the running web UI once on a fresh
  # install so Settings → Plugin Market appears without manual intervention.
  ensureMarket = pkgs.writeShellScript "dsh-market-ensure" ''
        set -eu
        export PATH=/run/current-system/sw/bin:$PATH
        PROFILE_DIR="${homeDir}/.dsh/profiles/web"
        mkdir -p "$PROFILE_DIR"

        installed=0
        if ! grep -q '"dshmarket"' "$PROFILE_DIR/package.json" 2>/dev/null; then
          echo "dsh-market: installing dshmarket into the web profile..."
          dsh plugin --profile web add dshmarket \
            || { echo "dsh-market: install failed (offline? pnpm?) — will retry on next login" >&2; exit 0; }
          installed=1
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

        if [ "$installed" = 1 ]; then
          export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
          systemctl --user restart dsh.service 2>/dev/null || true
        fi
  '';
in
{
  # Plugin market for dsh web: Settings → Plugin Market (browse the
  # awesome-dsh-plugin catalog, one-click install/update/uninstall).
  # Runs on every rebuild (as the user, so profile files stay user-owned)
  # and on every login (recovery after manual plugin churn) — same pattern
  # as dsh-tui-ru.
  system.activationScripts.dshMarketEnsure = lib.stringAfter [ "users" ] ''
    ${lib.getExe' pkgs.util-linux "runuser"} -u ${user} -- env HOME=${homeDir} ${ensureMarket} || true
  '';

  systemd.user.services.dsh-market-ensure = {
    enable = true;
    description = "dshmarket — ensure plugin market in the dsh web profile";
    after = [ "network.target" ];
    before = [ "dsh.service" ];
    wantedBy = [ "default.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = ensureMarket;
    };
  };
}
