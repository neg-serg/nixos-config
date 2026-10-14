{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.lib.neg) mainUser homeDir systemdUser;

  # The neg look for the TUI: the built-in palettes are upstream themes
  # (graphite/pastel/cobalt/...), none of them the muted navy/teal/violet the
  # rest of the system uses (files/kitty/theme.conf, neg.omp.json). dsh-TUI
  # discovers user themes as ~/.dsh-tui/themes/<name>.json (the file name is the
  # theme name) and persists the choice in ~/.dsh-tui/theme.json; the caretaker
  # below copies this file and seeds that preference.
  themeJson = ./dsh-tui-assets/themes/neg.json;

  # The tui profile's caretaker. It keeps the profile on the installed harness:
  # installs/upgrades the dsh-TUI plugin, keeps dsh-free-search, removes a
  # leftover @deepseek-ai store link (dsh's own profile module fallback owns
  # that tree and cannot write through the read-only link), prunes the retired
  # workflow row from the installed liangshen preset, rewrites the profile's
  # patch layer, seeds the repo-local plugin copies, and seeds the neg theme
  # plus the `en` default language. The profile itself is created by hand once
  # (see the `[ -d "$PROFILE_DIR" ] || exit 0` guard).
  # The plugin roster, its loader rows, the seed list and the search rows live
  # in dsh-terminal-plugins.nix; the agent-preset declarations (0.2.0 registry
  # rows: .agent-presets directories are dead) live in dsh-presets.nix.
  roster = import ./dsh-terminal-plugins.nix { inherit lib; };
  presets = import ./dsh-presets.nix { inherit pkgs; };

  # The profile ships `cordis.patch.yml` as an empty list; rows must replace
  # that `[]` (a second YAML root node is a parse error). The caretaker rewrites
  # the header comments plus its own rows, so a hand-edited or half-written file
  # heals on the next run.
  presetPatch = ./dsh-tui-preset-patch.py;

  # The dsh-TUI bundle's own liangshen preset still carries the 0.1.x
  # workflow-provider row next to its 0.2.0 replacement; the harness's static
  # compatibility preflight denies it and with it the whole preset. The pruner
  # drops that dead row from the installed copy (see its header).
  liangshenPrune = ./dsh-tui-liangshen-prune.py;

  # One-time XDG relocation of ~/.dsh / ~/.dsh-tui (idempotent; the caretaker
  # calls it on every run and leaves compatibility symlinks behind).
  xdgMigrate = pkgs.writeShellScript "dsh-xdg-migrate" (builtins.readFile ./dsh-xdg-migrate.sh);

  ensureTui = pkgs.writeShellScript "dsh-tui-ensure" (
    builtins.readFile (
      pkgs.replaceVars ./dsh-tui-ensure.sh {
        advisor = pkgs.copyPathToStore ./dsh-advisor;
        categoryPlugin = pkgs.copyPathToStore ./dsh-category-skill-reminder;
        ttsr = pkgs.copyPathToStore ./dsh-ttsr;
        presetPatch = pkgs.copyPathToStore presetPatch;
        liangshenPrune = pkgs.copyPathToStore liangshenPrune;
        themeJson = pkgs.copyPathToStore themeJson;
        inherit homeDir;
        inherit xdgMigrate;
        pluginSeeds = roster.seeds;
        pluginRows = lib.escapeShellArg roster.rows;
        searchRows = lib.escapeShellArg roster.searchRows;
        llmRows = lib.escapeShellArg roster.llmRows;
        presetData = presets.json;
      }
    )
  );
in
{
  # The profile caretaker runs as the user (it writes the profile's files) and
  # before the terminal UI starts.
  system.activationScripts.dshTuiEnsure = systemdUser.mkUserActivation {
    inherit pkgs;
    user = mainUser;
    home = homeDir;
    script = ensureTui;
  };

  systemd.user.services.dsh-tui-ensure = systemdUser.mkUserOneshot {
    description = "dsh-TUI — keep the tui profile on the installed harness";
    script = ensureTui;
    after = [ "network.target" ];
  };

  # Manual entry point: `systemctl --user start dsh-xdg-migrate`. The caretaker
  # already runs the same script on every rebuild/login; this unit is for
  # running it on demand (and for `--dry-run` via the plain script path).
  systemd.user.services.dsh-xdg-migrate = systemdUser.mkUserOneshot {
    description = "dsh — relocate ~/.dsh and ~/.dsh-tui into XDG directories";
    script = xdgMigrate;
  };

  # The neg theme for the TUI is seeded from the repo by the caretaker; the
  # preference file (~/.dsh-tui/theme.json) is the user's, so it is only written
  # while unset.
}
