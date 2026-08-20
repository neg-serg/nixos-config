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

  # dsh-delegate-task-retry: retry hint after failed subagent delegation.
  pkg = ./dsh-delegate-task-retry;

  ensure = pkgs.writeShellScript "dsh-delegate-task-retry-ensure" ''
        set -eu
        export PATH=/run/current-system/sw/bin:$PATH
        PROFILE_DIR="${homeDir}/.dsh/profiles/web"
        P="$PROFILE_DIR/node_modules/dsh-delegate-task-retry"
        mkdir -p "$P/lib"
        changed=0
        for f in package.json lib/index.js; do
          if [ ! -f "$P/$f" ]; then
            cp "${pkg}/$f" "$P/$f"
            changed=1
          fi
        done
        PATCH="$PROFILE_DIR/cordis.patch.yml"
        if ! grep -q 'dsh-delegate-task-retry' "$PATCH" 2>/dev/null; then
          cat >> "$PATCH" <<'YAML'

    # dsh-delegate-task-retry - retry hint after failed subagent delegation
    # (module: dsh-delegate-task-retry.nix).
    - insert:
        - id: delegate-task-retry
          name: dsh-delegate-task-retry
    YAML
          changed=1
        fi
        if [ "$changed" = 1 ]; then
          export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
          ${pkgs.neg.dsh-restart}
        fi
  '';
in
{
  system.activationScripts.dshDelegateTaskRetry = lib.stringAfter [ "users" "dshMarketEnsure" ] ''
    ${lib.getExe' pkgs.util-linux "runuser"} -u ${user} -- env HOME=${homeDir} ${ensure} || true
  '';

  systemd.user.services.dsh-delegate-task-retry = {
    enable = true;
    description = "dsh-delegate-task-retry — retry hint after failed subagent delegation";
    after = [
      "network.target"
      "dsh-market-ensure.service"
    ];
    before = [ "dsh.service" ];
    wantedBy = [ "default.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = ensure;
    };
  };
}
