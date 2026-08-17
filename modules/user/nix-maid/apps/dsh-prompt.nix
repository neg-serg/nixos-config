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

  # dsh-prompt: client-only composer placeholder tweak for the dsh web
  # profile — replaces the stock "Message the agent" (and its zh pair
  # "给智能体发消息") placeholder with a terminal-style "❯_" prompt. The
  # package is a plain directory in the profile node_modules (pnpm is
  # intentionally not used — the @deepseek-ai store symlink makes pnpm writes
  # fail with EROFS, see dsh-market.nix), registered through a profile patch
  # insert row, same as dsh-gui-tweaks. Files are written only when missing,
  # so local tweaks to client.js survive; the patch row is appended
  # idempotently.
  assets = ./dsh-prompt-assets;

  ensurePrompt = pkgs.writeShellScript "dsh-prompt-ensure" ''
    set -eu
    export PATH=/run/current-system/sw/bin:$PATH
    PROFILE_DIR="${homeDir}/.dsh/profiles/web"
    T="$PROFILE_DIR/node_modules/dsh-prompt"
    mkdir -p "$T/lib"
    for f in package.json lib/index.js lib/client.js; do
      if [ ! -f "$T/$f" ]; then
        cp "${assets}/$f" "$T/$f"
      fi
    done
    PATCH="$PROFILE_DIR/cordis.patch.yml"
    if ! grep -q 'dsh-prompt' "$PATCH" 2>/dev/null; then
      cat >> "$PATCH" <<'YAML'

# dsh-prompt - terminal-style composer placeholder (❯_ instead of the stock
# "Message the agent") (module: dsh-prompt.nix).
- insert:
    - id: dsh-prompt
      name: dsh-prompt
YAML
    fi
  '';
in
{
  # Apply on every nixos-rebuild (as the user, so profile files stay
  # user-owned) — same pattern as dsh-market-ensure. Runs after the market
  # ensure so a one-time pnpm install there cannot wipe the plugin dir first.
  system.activationScripts.dshPrompt = lib.stringAfter [ "users" "dshMarketEnsure" ] ''
    ${lib.getExe' pkgs.util-linux "runuser"} -u ${user} -- env HOME=${homeDir} ${ensurePrompt} || true
  '';

  # ...and on every login, so the plugin survives plugin re-installs made
  # after the last rebuild. Before dsh.service so the composition includes
  # the row when dsh boots.
  systemd.user.services.dsh-prompt = {
    enable = true;
    description = "dsh-prompt — terminal-style composer placeholder in the dsh web profile";
    after = [ "network.target" "dsh-market-ensure.service" ];
    before = [ "dsh.service" ];
    wantedBy = [ "default.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = ensurePrompt;
    };
  };
}
