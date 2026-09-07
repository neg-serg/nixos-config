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

  # dsh-archify: the Archify architecture-diagram skill for the dsh web
  # profile, installed from npm as @tt-a1i/archify-dsh@0.1.0 (prebuilt,
  # MIT). Archify turns a codebase or system description into a validated,
  # self-contained interactive HTML diagram (architecture / workflow /
  # sequence / data-flow / lifecycle). The npm package is a Skill-only dsh
  # bundle: it registers an archify-plugin filesystem Skill provider and
  # exposes the bundled Archify snapshot - no native render tools, so no
  # allowBuilds entry is needed.
  #
  # The version is pinned at @0.1.0: the upstream hub explicitly warns to
  # install the exact npm version rather than the Git source (Git installs
  # hit the allowBuilds approval prompt on first run). Ensure-if-missing
  # mirrors dsh-market.nix (package.json is the marker): a manual
  # `dsh plugin remove` is reverted on the next rebuild/login, and a failed
  # offline install retries on the next login.
  ensureArchify = pkgs.writeShellScript "dsh-archify-ensure" ''
    set -eu
    export PATH=/run/current-system/sw/bin:$PATH
    PROFILE_DIR="${homeDir}/.dsh/profiles/web"
    mkdir -p "$PROFILE_DIR"

    changed=0
    if ! grep -q '"@tt-a1i/archify-dsh"' "$PROFILE_DIR/package.json" 2>/dev/null; then
      echo "dsh-archify: installing @tt-a1i/archify-dsh@0.1.0 into the web profile..."
      # pnpm cannot write nested node_modules through the @deepseek-ai store
      # symlink (read-only /nix/store) and `dsh plugin add` re-links the
      # tree - park the symlink only for the duration of the pnpm operation
      # and restore it right after (same dance as dsh-market.nix).
      PROFILE_AI="$PROFILE_DIR/node_modules/@deepseek-ai"
      parked=0
      if [ -L "$PROFILE_AI" ]; then
        mv "$PROFILE_AI" "$PROFILE_AI.parked"
        parked=1
      fi
      restore_ai() {
        if [ "$parked" = 1 ] && [ ! -e "$PROFILE_AI" ]; then
          mv "$PROFILE_AI.parked" "$PROFILE_AI"
        fi
      }
      trap restore_ai EXIT
      # -w: the profile is a pnpm workspace root; pnpm 11 refuses `add`
      # from the root without it (see dsh-market.nix).
      if dsh plugin --profile web add "@tt-a1i/archify-dsh@0.1.0" -w; then
        changed=1
      else
        echo "dsh-archify: install failed - will retry on next login" >&2
      fi
      restore_ai
      trap - EXIT
    fi

    if [ "$changed" = 1 ]; then
      export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
      ${pkgs.neg.dsh-restart}
    fi
  '';
in
{
  # Apply on every nixos-rebuild (as the user, so profile files stay
  # user-owned) - same pattern as dsh-market-ensure. Runs after the market
  # ensure so the @deepseek-ai store symlink is back in place first.
  system.activationScripts.dshArchify = lib.stringAfter [ "users" "dshMarketEnsure" ] ''
    ${lib.getExe' pkgs.util-linux "runuser"} -u ${user} -- env HOME=${homeDir} ${ensureArchify} || true
  '';

  # ...and on every login, so the plugin survives plugin re-installs made
  # after the last rebuild. Before dsh.service so the skill is registered
  # when dsh boots.
  systemd.user.services.dsh-archify = {
    enable = true;
    description = "dsh-archify - ensure the Archify skill plugin in the dsh web profile";
    after = [
      "network.target"
      "dsh-market-ensure.service"
    ];
    before = [ "dsh.service" ];
    wantedBy = [ "default.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = ensureArchify;
    };
  };
}
