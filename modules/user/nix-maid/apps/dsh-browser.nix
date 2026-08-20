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

  # dsh-browser: CDP browser control (dedicated tabs; talks to Vivaldi/
  # chromium --remote-debugging-port). Server plugin, host plane — same
  # pattern as dsh-osm. The package is a plain directory in the profile
  # node_modules (pnpm is intentionally not used — the @deepseek-ai store
  # symlink makes pnpm writes fail with EROFS, see dsh-market.nix),
  # registered through a profile patch insert row. Files are written only
  # when missing, so local tweaks survive; to re-apply a changed copy from
  # this module, delete ~/.dsh/profiles/web/node_modules/dsh-browser and
  # restart dsh.
  pkg = ./dsh-browser;

  ensure = pkgs.writeShellScript "dsh-browser-ensure" ''
        set -eu
        export PATH=/run/current-system/sw/bin:$PATH
        PROFILE_DIR="${homeDir}/.dsh/profiles/web"
        P="$PROFILE_DIR/node_modules/dsh-browser"
        mkdir -p "$P/lib"
        changed=0
        for f in package.json lib/index.js; do
          if [ ! -f "$P/$f" ]; then
            cp "${pkg}/$f" "$P/$f"
            changed=1
          fi
        done
        PATCH="$PROFILE_DIR/cordis.patch.yml"
        if ! grep -q 'dsh-browser' "$PATCH" 2>/dev/null; then
          cat >> "$PATCH" <<'YAML'

    # dsh-browser - CDP browser control (dedicated tabs)
    # (module: dsh-browser.nix).
    - insert:
        - id: browser
          name: dsh-browser
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
  # Headless chromium for full CDP page automation (Vivaldi's CDP only answers
  # browser-level commands). Serves remote debugging on :9223 for dsh-browser.
  environment.systemPackages = [
    pkgs.chromium # headless CDP browser for dsh-browser page automation
  ];

  # Dedicated headless browser for the dsh-browser tool (private tabs only).
  systemd.user.services.browser-cdp = {
    enable = true;
    description = "dsh-browser — headless chromium CDP endpoint (:9223)";
    after = [ "network.target" ];
    wantedBy = [ "default.target" ];
    serviceConfig = {
      Type = "simple";
      Restart = "on-failure";
      ExecStart = "${pkgs.chromium}/bin/chromium --headless=new --remote-debugging-port=9223 --remote-allow-origins=* --user-data-dir=%h/.cache/dsh-browser --no-first-run --no-default-browser-check";
    };
  };

  # Apply on every nixos-rebuild (as the user, so profile files stay
  # user-owned) — same pattern as dsh-market-ensure / dsh-osm.
  system.activationScripts.dshBrowser = lib.stringAfter [ "users" "dshMarketEnsure" ] ''
    ${lib.getExe' pkgs.util-linux "runuser"} -u ${user} -- env HOME=${homeDir} ${ensure} || true
  '';

  # ...and on every login, so the plugin survives plugin re-installs made
  # after the last rebuild. Before dsh.service so the composition includes
  # the row when dsh boots.
  systemd.user.services.dsh-browser = {
    enable = true;
    description = "dsh-browser — ensure CDP browser tool in the dsh web profile";
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
