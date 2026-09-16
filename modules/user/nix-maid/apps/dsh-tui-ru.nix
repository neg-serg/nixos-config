{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.lib.neg) mainUser homeDir;
  systemdUser = import (config.lib.neg.path "lib/systemd-user.nix") { inherit lib; };

  # ── Tianshu Russian layer (dormant since the dsh-TUI switch) ────────────
  # The `tui` profile used to run the Tianshu TUI
  # (@huiliyi37/dsh-tianshu-tui), whose interface is hardcoded Chinese with no
  # language switch. The translation map (i18n.json) and the idempotent patcher
  # (patch.mjs) localized it to Russian; gen.mjs regenerates the map against a
  # newer bundle after an upgrade.
  #
  # Since 2026-09 the profile runs dsh-TUI (@deepseek-harness-tui/dsh-tui) — a
  # different codebase with a built-in `zh`/`en` switch and no Russian
  # dictionary. Its bundle does not match the glob in runPatch below, so this
  # layer is a no-op. It stays wired on purpose: reverting the package pin in
  # dsh-tui-ensure.sh back to Tianshu restores the Russian UI without
  # re-adding the module. Note that themes/neg.json was re-keyed to the
  # dsh-TUI custom-theme schema at the same time, so a revert also needs the
  # Tianshu-format theme file back from git history.
  i18nJson = ./dsh-tui-ru-assets/i18n.json;
  patcher = ./dsh-tui-ru-assets/patch.mjs;
  # The neg look for the TUI: the built-in palettes are upstream themes
  # (cobalt/graphite/pastel/...), none of them the muted navy/teal/violet the
  # rest of the system uses (files/kitty/theme.conf, neg.omp.json). dsh-TUI
  # discovers user themes as ~/.dsh-tui/themes/<name>.json (the file name is
  # the theme name) and persists the choice in ~/.dsh-tui/theme.json; the
  # caretaker below copies this file and seeds that preference.
  themeJson = ./dsh-tui-ru-assets/themes/neg.json;

  # Patch every installed dsh-tianshu-tui bundle under ~/.dsh/profiles.
  # Idempotent (marker file); safe to run as root from an activation script.
  # With dsh-TUI installed the loop matches nothing and exits 0.
  runPatch = pkgs.writeShellScript "dsh-tui-ru-patch" ''
    set +e
    for bundle in ${homeDir}/.dsh/profiles/*/node_modules/@huiliyi37/dsh-tianshu-tui/lib/index.js; do
      [ -f "$bundle" ] || continue
      ${lib.getExe pkgs.nodejs} ${patcher} ${i18nJson} "$bundle" \
        || echo "dsh-tui-ru: patch failed for $bundle" >&2
    done
    exit 0
  '';

  # The tui profile's caretaker. It keeps the profile on the installed harness:
  # installs/upgrades the dsh-TUI plugin, keeps dsh-free-search, removes a
  # leftover @deepseek-ai store link (dsh's own profile module fallback owns
  # that tree now and cannot write through the read-only link), rewrites the
  # profile's patch layer, seeds the repo-local plugin copies, and seeds the neg
  # theme plus the `en` default language. The profile itself is created by hand
  # once (see the `[ -d "$PROFILE_DIR" ] || exit 0` guard).
  # The plugin roster, its loader rows, the seed list and the search rows are
  # shared with the martty profile — see dsh-terminal-plugins.nix.
  roster = import ./dsh-terminal-plugins.nix { inherit lib; };

  # The profile ships `cordis.patch.yml` as an empty list; rows must replace
  # that `[]` (a second YAML root node is a parse error). The caretaker rewrites
  # the header comments plus its own rows, so a hand-edited or half-written file
  # heals on the next run. The extra arguments tell the shared script which
  # preset row id this profile's TUI bundle exposes and that the bundle already
  # carries its own code-runtime row.
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
  # Apply on every nixos-rebuild (runs as root; bundles live under the user
  # home, so a rebuild after reinstall reproduces the Russian UI of a Tianshu
  # bundle). A no-op while the profile runs dsh-TUI.
  system.activationScripts.dshTuiRu = lib.stringAfter [ "users" ] ''
    ${runPatch} || true
  '';

  # ...and on every login, so the patch survives plugin re-installs made
  # after the last rebuild.
  systemd.user.services.dsh-tui-ru = {
    enable = true;
    description = "dsh-tianshu-tui — apply Russian UI patch (dormant under dsh-TUI)";
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
    description = "dsh-TUI — keep the tui profile on the installed harness";
    script = ensureTui;
    after = [ "network.target" ];
  };

  # The Tianshu self-updater (the self-update-park-harness fix in patch.mjs)
  # re-applied the Russian patch through this helper right after it installed a
  # bundle. dsh-TUI ships its own updater and needs no repatch hook; the helper
  # stays as part of the dormant Tianshu layer.
  users.users.${mainUser}.maid.file.home.".local/bin/dsh-tui-repatch" = {
    source = runPatch;
    executable = true;
  };
}
