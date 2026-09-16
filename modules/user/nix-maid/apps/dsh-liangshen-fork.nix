{
  config,
  pkgs,
  ...
}:
let
  inherit (config.lib.neg) mainUser homeDir systemdUser;

  # dsh-liangshen-fork: the user's own fork of the LiangShen (anchored-standard)
  # agent preset, kept declaratively in ./dsh-liangshen-fork and synced into
  # ~/.dsh/.agent-presets/neg — the discovery root the dsh agent-presets
  # service scans for the preset picker (includeUserRoot). The preset id is
  # `neg` (renamed from `liangshen-fork` on the user's request); sessions and
  # the settings default reference `neg`. Unlike the upstream
  # @linxin666/dsh-liangshen plugin (which was unmounted — its patch row no
  # longer resolves), this needs no plugin: only the four preset files are
  # required for discovery.
  #
  # Sync is ALWAYS (not "only when missing" like dsh-osm): nothing wipes
  # .agent-presets on plugin re-installs, and the repo copy is the source of
  # truth — local edits to ~/.dsh/.agent-presets/neg are expected to be
  # reverted on rebuild. Edit ./dsh-liangshen-fork instead.
  # The default preset is set separately in ~/.dsh/settings.yaml under
  # `agent-presets.default` (read hot, per call — no dsh restart needed).
  pkg = ./dsh-liangshen-fork;

  ensureLiangshenFork = pkgs.writeShellScript "dsh-liangshen-fork-ensure" ''
    set -eu
    export PATH=/run/current-system/sw/bin:$PATH
    PRESET_ROOT="${homeDir}/.dsh/.agent-presets"
    PRESET_DIR="$PRESET_ROOT/neg"
    mkdir -p "$PRESET_DIR"
    cp -f "${pkg}/preset.yml" "$PRESET_DIR/preset.yml"
    cp -f "${pkg}/agent.cordis.yml" "$PRESET_DIR/agent.cordis.yml"
    cp -f "${pkg}/tool-bootstrap.mjs" "$PRESET_DIR/tool-bootstrap.mjs"
    cp -f "${pkg}/NOTICE" "$PRESET_DIR/NOTICE"
    # The upstream plugin's synced copy of the original LiangShen preset is
    # dead weight (the @linxin666/dsh-liangshen plugin is unmounted — its
    # patch row no longer resolves). Keep it removed so the picker shows only
    # the fork; delete the dir manually if the upstream is ever wanted back.
    rm -rf "$PRESET_ROOT/liangshen"
    # The pre-rename id must not linger in the picker either.
    rm -rf "$PRESET_ROOT/liangshen-fork"
    echo "dsh-liangshen-fork: synced preset into $PRESET_DIR (neg), removed upstream liangshen and old liangshen-fork id"
  '';
in
{
  # Apply on every nixos-rebuild (as the user, so ~/.dsh files stay user-owned)
  # and on every login, so the preset survives a fresh ~/.dsh or a manual
  # re-sync of .agent-presets — same pattern as dsh-market-ensure / dsh-osm.
  # No dsh.service restart: the roster and the settings default are read per
  # call (hot-reloaded).
  system.activationScripts.dshLiangshenFork = systemdUser.mkUserActivation {
    inherit pkgs;
    user = mainUser;
    home = homeDir;
    script = ensureLiangshenFork;
  };

  systemd.user.services.dsh-liangshen-fork = systemdUser.mkUserOneshot {
    description = "dsh-liangshen-fork — sync the neg (LiangShen fork) agent preset into ~/.dsh/.agent-presets";
    script = ensureLiangshenFork;
  };
}
