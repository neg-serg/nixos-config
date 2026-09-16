{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.lib.neg) mainUser homeDir;
  systemdUser = import (config.lib.neg.path "lib/systemd-user.nix") { inherit lib; };

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
  # that tree and cannot write through the read-only link), rewrites the
  # profile's patch layer, seeds the repo-local plugin copies, and seeds the neg
  # theme plus the `en` default language. The profile itself is created by hand
  # once (see the `[ -d "$PROFILE_DIR" ] || exit 0` guard).
  # The plugin roster, its loader rows, the seed list and the search rows live
  # in dsh-terminal-plugins.nix.
  roster = import ./dsh-terminal-plugins.nix { inherit lib; };

  # The profile ships `cordis.patch.yml` as an empty list; rows must replace
  # that `[]` (a second YAML root node is a parse error). The caretaker rewrites
  # the header comments plus its own rows, so a hand-edited or half-written file
  # heals on the next run.
  presetPatch = ./dsh-tui-preset-patch.py;

  ensureTui = pkgs.writeShellScript "dsh-tui-ensure" (
    builtins.readFile (
      pkgs.replaceVars ./dsh-tui-ensure.sh {
        advisor = pkgs.copyPathToStore ./dsh-advisor;
        categoryPlugin = pkgs.copyPathToStore ./dsh-category-skill-reminder;
        ttsr = pkgs.copyPathToStore ./dsh-ttsr;
        presetPatch = pkgs.copyPathToStore presetPatch;
        themeJson = pkgs.copyPathToStore themeJson;
        inherit homeDir;
        pluginSeeds = roster.seeds;
        pluginRows = lib.escapeShellArg roster.rows;
        searchRows = lib.escapeShellArg roster.searchRows;
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

  # The neg theme for the TUI is seeded from the repo by the caretaker; the
  # preference file (~/.dsh-tui/theme.json) is the user's, so it is only written
  # while unset.
}
