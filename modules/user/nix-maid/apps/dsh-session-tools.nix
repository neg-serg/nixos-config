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

  # dsh-session-tools: slash commands /rename, /status, /remember, /forget for
  # the dsh web GUI. Server-only plugin (no browser half): the commands surface
  # in the chat input once registered on the host 'commands' service.
  # Files are written only when missing, so local tweaks survive; to re-apply
  # a changed copy from this module, delete
  # ~/.dsh/profiles/web/node_modules/dsh-session-tools and restart dsh.
  pkg = ./dsh-session-tools;

  ensureTools = pkgs.writeShellScript "dsh-session-tools-ensure" ''
    set -eu
    export PATH=/run/current-system/sw/bin:$PATH
    PROFILE_DIR="${homeDir}/.dsh/profiles/web"
    P="$PROFILE_DIR/node_modules/dsh-session-tools"
    mkdir -p "$P/lib"
    changed=0
    for f in package.json lib/index.js; do
      if [ ! -f "$P/$f" ]; then
        cp "${pkg}/$f" "$P/$f"
        changed=1
      fi
    done
    PATCH="$PROFILE_DIR/cordis.patch.yml"
    if ! grep -q 'dsh-session-tools' "$PATCH" 2>/dev/null; then
      cat >> "$PATCH" <<'YAML'

    # dsh-session-tools - /rename, /status, /remember, /forget session conveniences.
    - insert:
        - id: dsh-session-tools
          name: dsh-session-tools
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
  # user-owned) — same pattern as dsh-market-ensure / dsh-mode.
  system.activationScripts.dshSessionTools = lib.stringAfter [ "users" "dshMarketEnsure" ] ''
    ${lib.getExe' pkgs.util-linux "runuser"} -u ${user} -- env HOME=${homeDir} ${ensureTools} || true
  '';

  # ...and on every login, so the plugin survives plugin re-installs made
  # after the last rebuild. Before dsh.service so the composition includes
  # the row when dsh boots.
  systemd.user.services.dsh-session-tools = {
    enable = true;
    description = "dsh-session-tools — ensure session-command plugin in the dsh web profile";
    after = [
      "network.target"
      "dsh-market-ensure.service"
    ];
    before = [ "dsh.service" ];
    wantedBy = [ "default.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = ensureTools;
    };
  };
}
