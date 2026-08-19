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

  # dsh-liangshen-fork: the user's own fork of the LiangShen (anchored-standard)
  # agent preset, kept declaratively in ./dsh-liangshen-fork and synced into
  # ~/.dsh/.agent-presets/<id> — the discovery root the dsh agent-presets
  # service scans for the preset picker (includeUserRoot). Unlike the upstream
  # @linxin666/dsh-liangshen plugin (which was unmounted — its patch row no
  # longer resolves), this needs no plugin: only the four preset files are
  # required for discovery.
  #
  # Sync is ALWAYS (not "only when missing" like dsh-osm): nothing wipes
  # .agent-presets on plugin re-installs, and the repo copy is the source of
  # truth — local edits to ~/.dsh/.agent-presets/liangshen-fork are expected
  # to be reverted on rebuild. Edit ./dsh-liangshen-fork instead.
  # The default preset is set separately in ~/.dsh/settings.yaml under
  # `agent-presets.default` (read hot, per call — no dsh restart needed).
  pkg = ./dsh-liangshen-fork;

  ensureLiangshenFork = pkgs.writeShellScript "dsh-liangshen-fork-ensure" ''
    set -eu
    export PATH=/run/current-system/sw/bin:$PATH
    PRESET_DIR="${homeDir}/.dsh/.agent-presets/liangshen-fork"
    mkdir -p "$PRESET_DIR"
    cp -f "${pkg}/preset.yml" "$PRESET_DIR/preset.yml"
    cp -f "${pkg}/agent.cordis.yml" "$PRESET_DIR/agent.cordis.yml"
    cp -f "${pkg}/tool-bootstrap.mjs" "$PRESET_DIR/tool-bootstrap.mjs"
    cp -f "${pkg}/NOTICE" "$PRESET_DIR/NOTICE"
    echo "dsh-liangshen-fork: synced preset into $PRESET_DIR"
  '';
in
{
  # Apply on every nixos-rebuild (as the user, so ~/.dsh files stay
  # user-owned) — same pattern as dsh-market-ensure / dsh-osm.
  system.activationScripts.dshLiangshenFork = lib.stringAfter [ "users" ] ''
    ${lib.getExe' pkgs.util-linux "runuser"} -u ${user} -- env HOME=${homeDir} ${ensureLiangshenFork} || true
  '';

  # ...and on every login, so the preset survives a fresh ~/.dsh or a
  # manual re-sync of .agent-presets. No dsh.service restart: the roster
  # and the settings default are read per call (hot-reloaded).
  systemd.user.services.dsh-liangshen-fork = {
    enable = true;
    description = "dsh-liangshen-fork — sync the LiangShen (fork) agent preset into ~/.dsh/.agent-presets";
    wantedBy = [ "default.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = ensureLiangshenFork;
    };
  };
}
