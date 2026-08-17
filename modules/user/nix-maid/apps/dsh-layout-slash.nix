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

  # dsh-layout-slash: in the dsh web composer, a leading "." — what the "/"
  # key produces under the ru layout — becomes "/" and the host switches the
  # Hyprland layout to us, so the rest of the message is typed in English.
  # The package is a plain directory in the profile node_modules (pnpm is
  # intentionally not used — the @deepseek-ai store symlink makes pnpm writes
  # fail with EROFS, see dsh-market.nix), registered through a profile patch
  # insert row, same as dsh-prompt / dsh-gui-tweaks. Files are written only
  # when missing, so local tweaks to client.js survive; the patch row is
  # appended idempotently.
  assets = ./dsh-layout-slash-assets;

  ensure = pkgs.writeShellScript "dsh-layout-slash-ensure" ''
    set -eu
    export PATH=/run/current-system/sw/bin:$PATH
    PROFILE_DIR="${homeDir}/.dsh/profiles/web"
    T="$PROFILE_DIR/node_modules/dsh-layout-slash"
    mkdir -p "$T/lib"
    for f in package.json lib/index.js lib/client.js; do
      if [ ! -f "$T/$f" ]; then
        cp "${assets}/$f" "$T/$f"
      fi
    done
    PATCH="$PROFILE_DIR/cordis.patch.yml"
    if ! grep -q 'dsh-layout-slash' "$PATCH" 2>/dev/null; then
      cat >> "$PATCH" <<'YAML'

# dsh-layout-slash - composer: a leading "." becomes "/" and the layout
# switches to English (module: dsh-layout-slash.nix).
- insert:
    - id: layout-slash
      name: dsh-layout-slash
YAML
    fi
  '';
in
{
  # Apply on every nixos-rebuild (as the user, so profile files stay
  # user-owned) — same pattern as dsh-market-ensure. Runs after the market
  # ensure so a one-time pnpm install there cannot wipe the plugin dir first.
  system.activationScripts.dshLayoutSlash = lib.stringAfter [ "users" "dshMarketEnsure" ] ''
    ${lib.getExe' pkgs.util-linux "runuser"} -u ${user} -- env HOME=${homeDir} ${ensure} || true
  '';

  # ...and on every login, so the plugin survives plugin re-installs made
  # after the last rebuild. Before dsh.service so the composition includes
  # the row when dsh boots.
  systemd.user.services.dsh-layout-slash = {
    enable = true;
    description = "dsh-layout-slash — leading dot → slash + us layout in the dsh web composer";
    after = [ "network.target" "dsh-market-ensure.service" ];
    before = [ "dsh.service" ];
    wantedBy = [ "default.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = ensure;
    };
  };
}
