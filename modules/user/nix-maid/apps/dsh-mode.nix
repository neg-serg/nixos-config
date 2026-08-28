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

  # dsh-mode: slash commands for the dsh web GUI — /mode lists available agent
  # presets or switches the default mode for new sessions, /fast and /smart
  # switch the default to the lean `fast` preset (and reasoning effort low) or
  # back to the full `neg` preset (effort high). Server-only plugin (no
  # browser half): commands surface in the chat input automatically once
  # registered on the host 'commands' service. The defaults live in the
  # agent-presets / agent-default-model settings namespaces (hot-reloaded, no
  # dsh restart needed for the settings themselves; the plugin code loads at
  # dsh start).
  # Files are copied when missing OR different from the repo copy (the repo is
  # the source of truth, like dsh-liangshen-fork): local tweaks under
  # node_modules/dsh-mode are reverted on rebuild. A changed copy restarts dsh
  # so the new plugin code is loaded.
  pkg = ./dsh-mode;

  ensureMode = pkgs.writeShellScript "dsh-mode-ensure" ''
    set -eu
    export PATH=/run/current-system/sw/bin:$PATH
    PROFILE_DIR="${homeDir}/.dsh/profiles/web"
    P="$PROFILE_DIR/node_modules/dsh-mode"
    mkdir -p "$P/lib"
    changed=0
    for f in package.json lib/index.js; do
      if [ ! -f "$P/$f" ] || ! cmp -s "${pkg}/$f" "$P/$f"; then
        cp -f "${pkg}/$f" "$P/$f"
        changed=1
      fi
    done
    PATCH="$PROFILE_DIR/cordis.patch.yml"
    if ! grep -q 'dsh-mode' "$PATCH" 2>/dev/null; then
      cat >> "$PATCH" <<'YAML'

    # dsh-mode - slash command /mode: list or switch the default agent preset.
    - insert:
        - id: dsh-mode
          name: dsh-mode
    YAML
      changed=1
    fi
    if [ "$changed" = 1 ]; then
      export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
      systemctl --user restart dsh.service 2>/dev/null || true
    fi
  '';
in
{
  # Apply on every nixos-rebuild (as the user, so profile files stay
  # user-owned) — same pattern as dsh-market-ensure / dsh-osm.
  system.activationScripts.dshMode = lib.stringAfter [ "users" "dshMarketEnsure" ] ''
    ${lib.getExe' pkgs.util-linux "runuser"} -u ${user} -- env HOME=${homeDir} ${ensureMode} || true
  '';

  # ...and on every login, so the plugin survives plugin re-installs made
  # after the last rebuild. Before dsh.service so the composition includes
  # the row when dsh boots.
  systemd.user.services.dsh-mode = {
    enable = true;
    description = "dsh-mode — ensure the /mode slash-command plugin in the dsh web profile";
    after = [
      "network.target"
      "dsh-market-ensure.service"
    ];
    before = [ "dsh.service" ];
    wantedBy = [ "default.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = ensureMode;
    };
  };
}
