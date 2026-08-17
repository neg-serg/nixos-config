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

  # dsh-osm: OpenStreetMap integration for the dsh web profile — the
  # osm_geocode / osm_reverse / osm_overpass / osm_route tools, the bundled
  # OSM-etiquette skill, and the Leaflet map card in the web GUI. The package
  # is a plain directory in the profile node_modules (pnpm is intentionally
  # not used — the @deepseek-ai store symlink makes pnpm writes fail with
  # EROFS, see dsh-market.nix), registered through a profile patch insert
  # row, same as dsh-gui-tweaks / dsh-terminal-ui. Files are written only
  # when missing, so local tweaks survive; to re-apply a changed copy from
  # this module, delete ~/.dsh/profiles/web/node_modules/dsh-osm and restart
  # dsh (systemctl --user restart dsh.service).
  pkg = ./dsh-osm;

  ensureOsm = pkgs.writeShellScript "dsh-osm-ensure" ''
        set -eu
        export PATH=/run/current-system/sw/bin:$PATH
        PROFILE_DIR="${homeDir}/.dsh/profiles/web"
        P="$PROFILE_DIR/node_modules/dsh-osm"
        mkdir -p "$P/lib" "$P/assets/leaflet/images"
        changed=0
        for f in \
          package.json \
          lib/index.js lib/tools.js lib/rate-limit.js lib/client.js \
          assets/osm-skill.md \
          assets/leaflet/leaflet.js assets/leaflet/leaflet.css
        do
          if [ ! -f "$P/$f" ]; then
            cp "${pkg}/$f" "$P/$f"
            changed=1
          fi
        done
        for img in layers.png layers-2x.png marker-icon.png marker-icon-2x.png marker-shadow.png; do
          if [ ! -f "$P/assets/leaflet/images/$img" ]; then
            cp "${pkg}/assets/leaflet/images/$img" "$P/assets/leaflet/images/$img"
            changed=1
          fi
        done
        PATCH="$PROFILE_DIR/cordis.patch.yml"
        if ! grep -q 'dsh-osm' "$PATCH" 2>/dev/null; then
          cat >> "$PATCH" <<'YAML'

    # dsh-osm - OpenStreetMap tools + Leaflet map card (module: dsh-osm.nix).
    - insert:
        - id: osm
          name: dsh-osm
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
  # user-owned) — same pattern as dsh-market-ensure. Runs after the market
  # ensure so a one-time pnpm install there cannot wipe the plugin dir first.
  system.activationScripts.dshOsm = lib.stringAfter [ "users" "dshMarketEnsure" ] ''
    ${lib.getExe' pkgs.util-linux "runuser"} -u ${user} -- env HOME=${homeDir} ${ensureOsm} || true
  '';

  # ...and on every login, so the plugin survives plugin re-installs made
  # after the last rebuild. Before dsh.service so the composition includes
  # the row when dsh boots.
  systemd.user.services.dsh-osm = {
    enable = true;
    description = "dsh-osm — ensure OpenStreetMap plugin in the dsh web profile";
    after = [
      "network.target"
      "dsh-market-ensure.service"
    ];
    before = [ "dsh.service" ];
    wantedBy = [ "default.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = ensureOsm;
    };
  };
}
