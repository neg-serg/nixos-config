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

  # dsh-selfheal: self-healing for the dsh web profile —
  #   server half: repairs semantically corrupt session logs (tool-result
  #   blocks with string content, broken zstd framing) at boot and on a
  #   15-min timer, with backups under ~/.dsh/selfheal-backups/ and a report
  #   at ~/.dsh/selfheal-report.json;
  #   client half: tolerates the DOM removeChild race that crashes
  #   conversation.composer.bar on session switches (composer collapses,
  #   chat input disappears).
  #
  # Canonical source is the dsh-web-ui fork checkout
  # (packages/dsh-selfheal): the profile node_modules entry is a symlink
  # into it, same pattern as dsh-gui-tweaks, so source edits apply on the
  # next dsh restart / page refresh — no rebuild needed. If the fork
  # checkout is missing the plugin is skipped with a warning.
  forkPackage = "${homeDir}/src/1st-level/@projects/dsh-web-ui/packages/dsh-selfheal";

  ensureSelfheal = pkgs.writeShellScript "dsh-selfheal-ensure" ''
        set -eu
        export PATH=/run/current-system/sw/bin:$PATH
        PROFILE_DIR="${homeDir}/.dsh/profiles/web"
        T="$PROFILE_DIR/node_modules/dsh-selfheal"
        if [ -d "${forkPackage}" ]; then
          if [ ! -L "$T" ]; then
            rm -rf -- "$T" 2>/dev/null || true
          fi
          ln -sfn "${forkPackage}" "$T"
        else
          echo "dsh-selfheal: fork checkout missing at ${forkPackage} — plugin not installed" >&2
        fi
        PATCH="$PROFILE_DIR/cordis.patch.yml"
        if ! grep -q 'selfheal' "$PATCH" 2>/dev/null; then
          cat >> "$PATCH" <<'YAML'

    # dsh-selfheal - auto-repair of corrupt session logs (boot + periodic) and
    # client-side composer crash guard (module: dsh-selfheal.nix).
    - insert:
        - id: selfheal
          name: dsh-selfheal
    YAML
        fi
  '';
in
{
  # Apply on every nixos-rebuild (as the user, so profile files stay
  # user-owned) — same pattern as dsh-gui-tweaks.
  system.activationScripts.dshSelfheal = lib.stringAfter [ "users" "dshMarketEnsure" ] ''
    ${lib.getExe' pkgs.util-linux "runuser"} -u ${user} -- env HOME=${homeDir} ${ensureSelfheal} || true
  '';

  # ...and on every login, so the plugin survives plugin re-installs made
  # after the last rebuild. Before dsh.service so the composition includes
  # the row when dsh boots.
  systemd.user.services.dsh-selfheal = {
    enable = true;
    description = "dsh-selfheal — ensure session-repair plugin in the dsh web profile";
    after = [
      "network.target"
      "dsh-market-ensure.service"
    ];
    before = [ "dsh.service" ];
    wantedBy = [ "default.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = ensureSelfheal;
    };
  };
}
