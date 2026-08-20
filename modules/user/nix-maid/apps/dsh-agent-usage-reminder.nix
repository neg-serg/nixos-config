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

  # dsh-agent-usage-reminder: advisory nudge to delegate repetitive manual
  # search/exploration to subagents (server plugin, host plane — same pattern
  # as repeat-tool-reminder / dsh-osm). The package is a plain directory in
  # the profile node_modules (pnpm is intentionally not used — the
  # @deepseek-ai store symlink makes pnpm writes fail with EROFS, see
  # dsh-market.nix), registered through a profile patch insert row. Files are
  # written only when missing, so local tweaks survive; to re-apply a changed
  # copy from this module, delete
  # ~/.dsh/profiles/web/node_modules/dsh-agent-usage-reminder and restart dsh.
  pkg = ./dsh-agent-usage-reminder;

  ensure = pkgs.writeShellScript "dsh-agent-usage-reminder-ensure" ''
        set -eu
        export PATH=/run/current-system/sw/bin:$PATH
        PROFILE_DIR="${homeDir}/.dsh/profiles/web"
        P="$PROFILE_DIR/node_modules/dsh-agent-usage-reminder"
        mkdir -p "$P/lib"
        changed=0
        for f in package.json lib/index.js; do
          if [ ! -f "$P/$f" ]; then
            cp "${pkg}/$f" "$P/$f"
            changed=1
          fi
        done
        PATCH="$PROFILE_DIR/cordis.patch.yml"
        if ! grep -q 'dsh-agent-usage-reminder' "$PATCH" 2>/dev/null; then
          cat >> "$PATCH" <<'YAML'

    # dsh-agent-usage-reminder - nudge to delegate repetitive search to subagents
    # (module: dsh-agent-usage-reminder.nix).
    - insert:
        - id: agent-usage-reminder
          name: dsh-agent-usage-reminder
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
  # Apply on every nixos-rebuild (as the user, so profile files stay
  # user-owned) — same pattern as dsh-market-ensure / dsh-osm.
  system.activationScripts.dshAgentUsageReminder = lib.stringAfter [ "users" "dshMarketEnsure" ] ''
    ${lib.getExe' pkgs.util-linux "runuser"} -u ${user} -- env HOME=${homeDir} ${ensure} || true
  '';

  # ...and on every login, so the plugin survives plugin re-installs made
  # after the last rebuild. Before dsh.service so the composition includes
  # the row when dsh boots.
  systemd.user.services.dsh-agent-usage-reminder = {
    enable = true;
    description = "dsh-agent-usage-reminder — ensure nudge plugin in the dsh web profile";
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
