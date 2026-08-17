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

  # dsh-gui-tweaks: client-only GUI behavior tweaks for the dsh web profile —
  # 1) number-key answers in ask-user question dialogs, Enter confirms the
  # selection (clicks Next/Submit), 2) bash tool rows expand by default,
  # 3) bash terminal output cap removed, 4) composer input focused by
  # default (on tab/window focus, session switch, fresh composer mount). The
  # package is a
  # plain directory in the profile node_modules (pnpm is intentionally not
  # used — the @deepseek-ai store symlink makes pnpm writes fail with EROFS,
  # see dsh-market.nix), registered through a profile patch insert row, same
  # as dsh-terminal-ui. Files are written only when missing, so local tweaks
  # to client.js survive; the patch row is appended idempotently.
  assets = ./dsh-gui-tweaks-assets;

  ensureTweaks = pkgs.writeShellScript "dsh-gui-tweaks-ensure" ''
    set -eu
    export PATH=/run/current-system/sw/bin:$PATH
    PROFILE_DIR="${homeDir}/.dsh/profiles/web"
    T="$PROFILE_DIR/node_modules/dsh-gui-tweaks"
    mkdir -p "$T/lib"
    for f in package.json lib/index.js lib/client.js; do
      if [ ! -f "$T/$f" ]; then
        cp "${assets}/$f" "$T/$f"
      fi
    done
    PATCH="$PROFILE_DIR/cordis.patch.yml"
    if ! grep -q 'gui-tweaks' "$PATCH" 2>/dev/null; then
      cat >> "$PATCH" <<'YAML'

# dsh-gui-tweaks - number-key answers + Enter confirmation in question
# dialogs, bash tool rows expanded by default, bash output uncapped,
# composer input focused by default (module: dsh-gui-tweaks.nix).
- insert:
    - id: gui-tweaks
      name: dsh-gui-tweaks
YAML
    fi
  '';
in
{
  # Apply on every nixos-rebuild (as the user, so profile files stay
  # user-owned) — same pattern as dsh-market-ensure. Runs after the market
  # ensure so a one-time pnpm install there cannot wipe the plugin dir first.
  system.activationScripts.dshGuiTweaks = lib.stringAfter [ "users" "dshMarketEnsure" ] ''
    ${lib.getExe' pkgs.util-linux "runuser"} -u ${user} -- env HOME=${homeDir} ${ensureTweaks} || true
  '';

  # ...and on every login, so the plugin survives plugin re-installs made
  # after the last rebuild. Before dsh.service so the composition includes
  # the row when dsh boots.
  systemd.user.services.dsh-gui-tweaks = {
    enable = true;
    description = "dsh-gui-tweaks — ensure GUI behavior tweaks in the dsh web profile";
    after = [ "network.target" "dsh-market-ensure.service" ];
    before = [ "dsh.service" ];
    wantedBy = [ "default.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = ensureTweaks;
    };
  };
}
