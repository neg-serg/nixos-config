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

  # dsh-debug: DAP debugging tool (debug over gdb/lldb-dap/dlv/debugpy,
  # ported from omp). Server plugin, host plane — same pattern as dsh-osm.
  # The package is a plain directory in the profile node_modules (pnpm is
  # intentionally not used — the @deepseek-ai store symlink makes pnpm writes
  # fail with EROFS, see dsh-market.nix), registered through a profile patch
  # insert row. Files are written only when missing, so local tweaks survive;
  # to re-apply a changed copy from this module, delete
  # ~/.dsh/profiles/web/node_modules/dsh-debug and restart dsh.
  pkg = ./dsh-debug;

  ensure = pkgs.writeShellScript "dsh-debug-ensure" ''
        set -eu
        export PATH=/run/current-system/sw/bin:$PATH
        PROFILE_DIR="${homeDir}/.dsh/profiles/web"
        P="$PROFILE_DIR/node_modules/dsh-debug"
        mkdir -p "$P/lib"
        changed=0
        for f in package.json lib/index.js; do
          if [ ! -f "$P/$f" ]; then
            cp "${pkg}/$f" "$P/$f"
            changed=1
          fi
        done
        PATCH="$PROFILE_DIR/cordis.patch.yml"
        if ! grep -q 'dsh-debug' "$PATCH" 2>/dev/null; then
          cat >> "$PATCH" <<'YAML'

    # dsh-debug - DAP debugging tool (gdb/lldb-dap/dlv/debugpy)
    # (module: dsh-debug.nix).
    - insert:
        - id: debug
          name: dsh-debug
    YAML
          changed=1
        fi
        if [ "$changed" = 1 ]; then
          export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
          ${pkgs.neg.dsh-restart}/bin/dsh-restart
        fi
  '';
in
{
  # Apply on every nixos-rebuild (as the user, so profile files stay
  # user-owned) — same pattern as dsh-market-ensure / dsh-osm.
  system.activationScripts.dshDebug = lib.stringAfter [ "users" "dshMarketEnsure" ] ''
    ${lib.getExe' pkgs.util-linux "runuser"} -u ${user} -- env HOME=${homeDir} ${ensure} || true
  '';

  # ...and on every login, so the plugin survives plugin re-installs made
  # after the last rebuild. Before dsh.service so the composition includes
  # the row when dsh boots.
  systemd.user.services.dsh-debug = {
    enable = true;
    description = "dsh-debug — ensure DAP debugging tool in the dsh web profile";
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
