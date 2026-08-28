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

  # dsh-fast: the lean low-token agent preset (see ./dsh-fast/agent.cordis.yml).
  # Synced into ~/.dsh/.agent-presets/fast — the discovery root the dsh
  # agent-presets service scans for the preset picker. The preset id is `fast`.
  #
  # Sync is ALWAYS (repo copy is the source of truth, same as
  # dsh-liangshen-fork): nothing wipes .agent-presets on plugin re-installs,
  # and local edits to ~/.dsh/.agent-presets/fast are reverted on rebuild.
  #
  # The default preset is set separately in ~/.dsh/settings.yaml under
  # `agent-presets.default` (read hot, per call — no dsh restart needed);
  # the /fast and /smart slash commands (dsh-mode plugin) switch it together
  # with agent-default-model.reasoningEffort.
  pkg = ./dsh-fast;

  ensureFast = pkgs.writeShellScript "dsh-fast-ensure" ''
    set -eu
    export PATH=/run/current-system/sw/bin:$PATH
    PRESET_ROOT="${homeDir}/.dsh/.agent-presets"
    PRESET_DIR="$PRESET_ROOT/fast"
    mkdir -p "$PRESET_DIR"
    cp -f "${pkg}/preset.yml" "$PRESET_DIR/preset.yml"
    cp -f "${pkg}/agent.cordis.yml" "$PRESET_DIR/agent.cordis.yml"
    cp -f "${pkg}/NOTICE" "$PRESET_DIR/NOTICE"
    echo "dsh-fast: synced preset into $PRESET_DIR (fast)"
  '';
in
{
  # Apply on every nixos-rebuild (as the user, so ~/.dsh files stay
  # user-owned) — same pattern as dsh-liangshen-fork.
  system.activationScripts.dshFast = lib.stringAfter [ "users" ] ''
    ${lib.getExe' pkgs.util-linux "runuser"} -u ${user} -- env HOME=${homeDir} ${ensureFast} || true
  '';

  # ...and on every login, so the preset survives a fresh ~/.dsh or a
  # manual re-sync of .agent-presets. No dsh.service restart: the roster
  # and the settings default are read per call (hot-reloaded).
  systemd.user.services.dsh-fast = {
    enable = true;
    description = "dsh-fast — sync the fast (lean) agent preset into ~/.dsh/.agent-presets";
    wantedBy = [ "default.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = ensureFast;
    };
  };
}
