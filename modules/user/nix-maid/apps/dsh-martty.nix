{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.lib.neg) mainUser homeDir;
  systemdUser = import (config.lib.neg.path "lib/systemd-user.nix") { inherit lib; };

  # The plugin roster shared with the tui profile (dsh-tui-ru.nix): Martty is a
  # second terminal UI over the same harness, so it mounts the same host/agent
  # plugins and therefore needs the same profile layer.
  roster = import ./dsh-terminal-plugins.nix { inherit lib; };

  # The martty profile's caretaker. It keeps the profile on the installed
  # harness: installs/upgrades the Martty package, installs dsh-free-search,
  # relinks the profile @deepseek-ai to the harness tree, writes the loader rows
  # and seeds the repo-local plugins. Unlike the tui profile the user does not
  # create it by hand — the first run initializes it.
  ensureMartty = pkgs.writeShellScript "dsh-martty-ensure" (
    builtins.readFile (
      pkgs.replaceVars ./dsh-martty-ensure.sh {
        advisor = pkgs.copyPathToStore ./dsh-advisor;
        categoryPlugin = pkgs.copyPathToStore ./dsh-category-skill-reminder;
        ttsr = pkgs.copyPathToStore ./dsh-ttsr;
        presetPatch = pkgs.copyPathToStore ./dsh-tui-preset-patch.py;
        inherit homeDir;
        pluginSeeds = roster.seeds;
        pluginRows = lib.escapeShellArg roster.rows;
        searchRows = lib.escapeShellArg roster.searchRows;
        dsh = pkgs.neg.dsh;
      }
    )
  );
in
{
  # Runs as the user (it writes the profile's files), on every rebuild and on
  # every login, exactly like the tui profile caretaker — so a rebuild after a
  # `dsh plugin add` or an upgrade re-applies the rows and seeds.
  system.activationScripts.dshMarttyEnsure = systemdUser.mkUserActivation {
    inherit pkgs;
    user = mainUser;
    home = homeDir;
    script = ensureMartty;
  };

  systemd.user.services.dsh-martty-ensure = systemdUser.mkUserOneshot {
    description = "dsh martty profile — keep the Martty TUI on the installed harness";
    script = ensureMartty;
    after = [ "network.target" ];
  };

  # The UI itself is deliberately NOT patched: Martty's interface is English
  # (its bundle carries no Chinese UI literals), so the tui profile's Russian
  # translation map — and the Tianshu theme/status-line wiring — do not apply.
  # `dsh-martty` (dsh.nix) launches the profile.
}
