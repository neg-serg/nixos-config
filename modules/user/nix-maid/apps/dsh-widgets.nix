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

  # dsh-widgets: general-purpose widgets for the dsh web profile — a `json`
  # tool with a collapsible syntax-highlighted JSON tree card, readable
  # cards for subagent / subagent_fork / workflow / ralph / goal / jobs /
  # list_agents tool calls (which otherwise fall back to the generic "Tool
  # call" row with a raw JSON dump; the subagent cards also show the full
  # prompt), and a DOM transform that turns the "subagent-settled" notice
  # rows (whose closing message used to render as "Unknown content block"
  # JSON dumps) into a readable card with the child's status and closing
  # message. The `bash_live` streaming tool is enabled in this deployment
  # (deployment flag `enableBashLive` in the cordis.patch.yml row below; the
  # plugin default stays off, see lib/index.js). The package is a
  # plain directory in the
  # profile node_modules (pnpm is intentionally not used — the @deepseek-ai
  # store symlink makes pnpm writes fail with EROFS, see dsh-market.nix),
  # registered through a profile patch insert row, same as dsh-osm /
  # dsh-terminal-ui. Files are written only when missing, so local tweaks
  # survive; to re-apply a changed copy from this module, delete
  # ~/.dsh/profiles/web/node_modules/dsh-widgets and restart dsh
  # (systemctl --user restart dsh.service).
  pkg = ./dsh-widgets;

  ensureWidgets = pkgs.writeShellScript "dsh-widgets-ensure" ''
            set -eu
            export PATH=/run/current-system/sw/bin:$PATH
            PROFILE_DIR="${homeDir}/.dsh/profiles/web"
            P="$PROFILE_DIR/node_modules/dsh-widgets"
            mkdir -p "$P/lib"
            changed=0
            for f in \
              package.json \
              lib/index.js lib/tools.js lib/client.js
            do
              if [ ! -f "$P/$f" ]; then
                cp "${pkg}/$f" "$P/$f"
                changed=1
              fi
            done
            PATCH="$PROFILE_DIR/cordis.patch.yml"
            if ! grep -q 'dsh-widgets' "$PATCH" 2>/dev/null; then
              cat >> "$PATCH" <<'YAML'

    # dsh-widgets - json tool + JSON tree card, subagent/workflow/ralph/goal/jobs cards, and the
    # bash_live streaming tool (module: dsh-widgets.nix). bash_live is enabled in this
    # deployment (enableBashLive) — safe since the staged dsh-session patch marks
    # tool/bash-live-* events ignorable (packages/dsh/patch-widgets.py).
    - insert:
        - id: widgets
          name: dsh-widgets
          config:
            enableBashLive: true
    YAML
              changed=1
            elif ! grep -q 'enableBashLive' "$PATCH" 2>/dev/null; then
              # Upgrade a widgets row written before the bash_live opt-in: add the
              # config block under the insert entry (exact match only, idempotent).
              if python3 - "$PATCH" <<'PY'
    import sys

    path = sys.argv[1]
    text = open(path).read()
    old = "- insert:\n    - id: widgets\n      name: dsh-widgets\n\n"
    new = "- insert:\n    - id: widgets\n      name: dsh-widgets\n      config:\n        enableBashLive: true\n\n"
    if old in text:
        open(path, "w").write(text.replace(old, new, 1))
        print("dsh-widgets: enableBashLive config added to the widgets row")
        raise SystemExit(0)
    print("dsh-widgets: widgets row present but old snippet not found; leaving as-is")
    raise SystemExit(1)
    PY
              then
                changed=1
              else
                echo "dsh-widgets: warning: could not upgrade the widgets row (unexpected format)" >&2
              fi
            fi
            if [ "$changed" = 1 ]; then
              export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
              ${pkgs.neg.dsh-restart}/bin/dsh-restart
            fi
  '';
in
{
  # Apply on every nixos-rebuild (as the user, so profile files stay
  # user-owned) — same pattern as dsh-market-ensure. Runs after the market
  # ensure so a one-time pnpm install there cannot wipe the plugin dir first.
  system.activationScripts.dshWidgets = lib.stringAfter [ "users" "dshMarketEnsure" ] ''
    ${lib.getExe' pkgs.util-linux "runuser"} -u ${user} -- env HOME=${homeDir} ${ensureWidgets} || true
  '';

  # ...and on every login, so the plugin survives plugin re-installs made
  # after the last rebuild. Before dsh.service so the composition includes
  # the row when dsh boots.
  systemd.user.services.dsh-widgets = {
    enable = true;
    description = "dsh-widgets — ensure json/agent-activity widgets in the dsh web profile";
    after = [
      "network.target"
      "dsh-market-ensure.service"
    ];
    before = [ "dsh.service" ];
    wantedBy = [ "default.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = ensureWidgets;
    };
  };
}
