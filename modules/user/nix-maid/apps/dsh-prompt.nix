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
  # "给智能体发消息") placeholder with a terminal-style "❯_" prompt.
  #
  # Canonical source is the dsh-web-ui fork checkout (packages/dsh-prompt):
  # the profile node_modules entry is a symlink into it, same pattern as
  # dsh-terminal-ui in dsh-market.nix, so source edits apply on the next page
  # refresh — no rebuild needed. If the fork checkout is missing the plugin is
  # skipped with a warning (fresh machine before `git clone`).
  forkPackage = "${homeDir}/src/1st-level/@projects/dsh-web-ui/packages/dsh-prompt";

  ensurePrompt = pkgs.writeShellScript "dsh-prompt-ensure" ''
    set -eu
    export PATH=/run/current-system/sw/bin:$PATH
    PROFILE_DIR="${homeDir}/.dsh/profiles/web"
    T="$PROFILE_DIR/node_modules/dsh-prompt"
    if [ -d "${forkPackage}" ]; then
      # Replace a plain copy (from before the fork migration) with the symlink.
      if [ ! -L "$T" ]; then
        rm -rf -- "$T" 2>/dev/null || true
      fi
      ln -sfn "${forkPackage}" "$T"
    else
      echo "dsh-prompt: fork checkout missing at ${forkPackage} — plugin not installed" >&2
    fi
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
