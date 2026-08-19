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

  # dsh-mobile: slash command /mobile for the dsh web GUI — connect the
  # Android phone (adb over USB or WiFi) and start scrcpy mirroring on the
  # desktop. Server-only plugin (no browser half): the command surfaces in the
  # chat input automatically once registered on the host 'commands' service.
  # Connection logic lives in the `phone` helper (packages/local-bin/bin/phone);
  # /mobile [ip] connects, remembers the IP, and launches scrcpy detached.
  # Files are written only when missing, so local tweaks survive; to re-apply
  # a changed copy from this module, delete
  # ~/.dsh/profiles/web/node_modules/dsh-mobile and restart dsh.
  pkg = ./dsh-mobile;

  ensureMobile = pkgs.writeShellScript "dsh-mobile-ensure" ''
        set -eu
        export PATH=/run/current-system/sw/bin:$PATH
        PROFILE_DIR="${homeDir}/.dsh/profiles/web"
        P="$PROFILE_DIR/node_modules/dsh-mobile"
        mkdir -p "$P/lib"
        changed=0
        for f in package.json lib/index.js; do
          if [ ! -f "$P/$f" ]; then
            cp "${pkg}/$f" "$P/$f"
            changed=1
          fi
        done
        PATCH="$PROFILE_DIR/cordis.patch.yml"
        if ! grep -q 'dsh-mobile' "$PATCH" 2>/dev/null; then
          cat >> "$PATCH" <<'YAML'

    # dsh-mobile - slash command /mobile: connect the Android phone (adb
    # USB/WiFi) and start scrcpy mirroring; /mobile status shows adb devices.
    - insert:
        - id: dsh-mobile
          name: dsh-mobile
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
  # user-owned) — same pattern as dsh-market-ensure / dsh-osm / dsh-mode.
  system.activationScripts.dshMobile = lib.stringAfter [ "users" "dshMarketEnsure" ] ''
    ${lib.getExe' pkgs.util-linux "runuser"} -u ${user} -- env HOME=${homeDir} ${ensureMobile} || true
  '';

  # ...and on every login, so the plugin survives plugin re-installs made
  # after the last rebuild. Before dsh.service so the composition includes
  # the row when dsh boots.
  systemd.user.services.dsh-mobile = {
    enable = true;
    description = "dsh-mobile — ensure the /mobile slash-command plugin in the dsh web profile";
    after = [
      "network.target"
      "dsh-market-ensure.service"
    ];
    before = [ "dsh.service" ];
    wantedBy = [ "default.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = ensureMobile;
    };
  };
}
