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

  # dsh-json-error-recovery: corrective reminder after failed edit/write
  # tools (harness hook from oh-my-opencode backlog). Server plugin, host
  # plane — same pattern as dsh-read-tags / dsh-osm. The package is a plain
  # directory in the profile node_modules, registered through a profile patch
  # insert row. Files are written only when missing, so local tweaks survive;
  # to re-apply a changed copy from this module, delete
  # ~/.dsh/profiles/web/node_modules/dsh-json-error-recovery and restart dsh.
  pkg = ./dsh-json-error-recovery;

  ensure = pkgs.writeShellScript "dsh-json-error-recovery-ensure" ''
        set -eu
        export PATH=/run/current-system/sw/bin:$PATH
        PROFILE_DIR="${homeDir}/.dsh/profiles/web"
        P="$PROFILE_DIR/node_modules/dsh-json-error-recovery"
        mkdir -p "$P/lib"
        changed=0
        for f in package.json lib/index.js; do
          if [ ! -f "$P/$f" ]; then
            cp "${pkg}/$f" "$P/$f"
            changed=1
          fi
        done
        PATCH="$PROFILE_DIR/cordis.patch.yml"
        if ! grep -q 'dsh-json-error-recovery' "$PATCH" 2>/dev/null; then
          cat >> "$PATCH" <<'YAML'

    # dsh-json-error-recovery - corrective hint after failed edit/write tools
    # (module: dsh-json-error-recovery.nix).
    - insert:
        - id: json-error-recovery
          name: dsh-json-error-recovery
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
  system.activationScripts.dshJsonErrorRecovery = lib.stringAfter [ "users" "dshMarketEnsure" ] ''
    ${lib.getExe' pkgs.util-linux "runuser"} -u ${user} -- env HOME=${homeDir} ${ensure} || true
  '';

  systemd.user.services.dsh-json-error-recovery = {
    enable = true;
    description = "dsh-json-error-recovery — corrective hint after failed edit/write tools";
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
