{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.lib.neg) mainUser homeDir;
  systemdUser = import (config.lib.neg.path "lib/systemd-user.nix") { inherit lib; };

  # dsh-tianshu-tui hardcodes its UI in Chinese with no language switch.
  # Assets below localize it to Russian: the translation map (i18n.json) and
  # the idempotent patcher (patch.mjs). gen.mjs regenerates the map against a
  # newer bundle when the plugin is upgraded.
  i18nJson = ./dsh-tui-ru-assets/i18n.json;
  patcher = ./dsh-tui-ru-assets/patch.mjs;
  # The neg look for the TUI itself: the built-in palettes are upstream themes
  # (cobalt/graphite/pastel/...), none of them the muted navy/teal/violet the
  # rest of the system uses (files/kitty/theme.conf, neg.omp.json). The TUI
  # loads custom themes from ~/.dsh-tui/themes/*.json and references them as
  # `custom:<name>`.
  themeJson = ./dsh-tui-ru-assets/themes/neg.json;

  # Patch every installed dsh-tianshu-tui bundle under ~/.dsh/profiles.
  # Idempotent (marker file); safe to run as root from an activation script.
  runPatch = pkgs.writeShellScript "dsh-tui-ru-patch" ''
    set +e
    for bundle in ${homeDir}/.dsh/profiles/*/node_modules/@huiliyi37/dsh-tianshu-tui/lib/index.js; do
      [ -f "$bundle" ] || continue
      ${lib.getExe pkgs.nodejs} ${patcher} ${i18nJson} "$bundle" \
        || echo "dsh-tui-ru: patch failed for $bundle" >&2
    done
    exit 0
  '';

  # The TUI profile's caretaker. Three things have to hold for the terminal UI
  # to work on this harness, and pnpm undoes two of them on every install:
  #
  # 1. dsh-tianshu-tui must be recent enough for the installed harness. Releases
  #    <= 0.1.2-rc.6 read `session.events`, an array the 0.1.5 Session no longer
  #    exposes, so the TUI died at startup with
  #    "attach failed: TypeError: session.events is not iterable"; the rc.29 line
  #    reads the current session face (the same break the plugin family hit).
  # 2. The profile's @deepseek-ai tree must BE the harness tree. pnpm installs
  #    the TUI plugin's own peer copies (0.1.2-rc.x), and those ship an older
  #    agent-presets schema — the shipped `standard` preset then fails to mount
  #    ("$.prefix missing required value"). Linking the harness tree keeps one
  #    instance per package (the web profile used the same relink before it was
  #    removed in 2026-09).
  # 3. The base default preset is `standard`, which the harness build removes
  #    (packages/dsh/default.nix): the profile fallback below names `neg`, and the
  #    TUI's own hardcoded DEFAULT_PRESET_ID is rewritten to `neg` by the
  #    translation patcher (dsh-tui-ru-assets/patch.mjs) — otherwise every start
  #    warns that the default preset did not apply. settings.yaml still wins over
  #    the row's fallback.
  # The profile ships `cordis.patch.yml` as an empty list; rows must replace
  # that `[]`, not be appended after it (a second YAML root node is a parse
  # error). Idempotent through its own marker comment.
  # The plugin roster, its loader rows, the seed list and the search rows are
  # shared with the martty profile — see dsh-terminal-plugins.nix.
  roster = import ./dsh-terminal-plugins.nix { inherit lib; };

  # The profile ships `cordis.patch.yml` as an empty list; rows must replace
  # that `[]` (a second YAML root node is a parse error). The caretaker rewrites
  # the header comments plus its own row, so a hand-edited or half-written file
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
        dsh = pkgs.neg.dsh;
      }
    )
  );
in
{
  # Apply on every nixos-rebuild (runs as root; bundles live under the user
  # home, so a rebuild after reinstall reproduces the Russian UI).
  system.activationScripts.dshTuiRu = lib.stringAfter [ "users" ] ''
    ${runPatch} || true
  '';

  # ...and on every login, so the patch survives plugin re-installs made
  # after the last rebuild.
  systemd.user.services.dsh-tui-ru = {
    enable = true;
    description = "dsh-tianshu-tui — apply Russian UI patch";
    wantedBy = [ "default.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = runPatch;
    };
  };

  # The profile caretaker runs as the user (it writes the profile's files) and
  # before the terminal UI starts; the Russian patch above only rewrites strings
  # and stays independent of it.
  system.activationScripts.dshTuiEnsure = systemdUser.mkUserActivation {
    inherit pkgs;
    user = mainUser;
    home = homeDir;
    script = ensureTui;
  };

  systemd.user.services.dsh-tui-ensure = systemdUser.mkUserOneshot {
    description = "dsh-tianshu-tui — keep the TUI profile on the installed harness";
    script = ensureTui;
    after = [ "network.target" ];
  };

  # The TUI self-updater (the self-update-park-harness fix in patch.mjs)
  # re-applies the Russian patch through this helper right after it installs a
  # bundle, before the host can restart into it — a raw npm release is
  # Chinese-only. Same script as the login/activation patch services.
  users.users.${mainUser}.maid.file.home.".local/bin/dsh-tui-repatch" = {
    source = runPatch;
    executable = true;
  };
}
