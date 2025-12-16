{
  lib,
  config,
  pkgs,
  ...
}:
with lib;
  mkIf (config.features.gui.enable or false) (lib.mkMerge [
    # Generate ~/.local/bin scripts from packages/local-bin
    {
      users.users.neg.maid.file.home = let
        # Path to the source directories
        binDir = config.neg.repoRoot + "/packages/local-bin/bin";
        scriptsDir = config.neg.repoRoot + "/packages/local-bin/scripts";

        # Python library paths for special scripts
        sp = pkgs.python3.sitePackages;
        libpp = "${pkgs.neg.pretty_printer}/${sp}";
        libcolored = "${pkgs.python3Packages.colored}/${sp}";

        # 1. Scripts from packages/local-bin/bin
        # We filter for regular files.
        binFiles =
          if builtins.pathExists binDir
          then lib.filterAttrs (_: v: v == "regular") (builtins.readDir binDir)
          else {};

        # Scripts to skip automatic generation for (handled specially below)
        autoSkip = ["ren"];

        # Helper to generate the home.file entry
        mkAuto = name: {
          name = ".local/bin/${name}";
          value = {
            executable = true;
            text = builtins.readFile (binDir + "/${name}");
          };
        };

        autoEntries = builtins.listToAttrs (
          map mkAuto (lib.filter (n: !(lib.elem n autoSkip)) (builtins.attrNames binFiles))
        );

        # 2. Scripts from packages/local-bin/scripts
        # These were manually listed in the original config, let's keep that explicit list
        # or map them all if we prefer. The original mapped them all but had special cases.
        # Let's map them all but exclude the special ones.
        scriptFiles =
          if builtins.pathExists scriptsDir
          then lib.filterAttrs (_: v: v == "regular") (builtins.readDir scriptsDir)
          else {};

        scriptSkip = ["ren" "vid-info.py"]; # These need substitution

        mkScriptAuto = name: {
          name = ".local/bin/${name}";
          value = {
            executable = true;
            text = builtins.readFile (scriptsDir + "/${name}");
          };
        };

        scriptEntries = builtins.listToAttrs (
          map mkScriptAuto (lib.filter (n: !(lib.elem n scriptSkip)) (builtins.attrNames scriptFiles))
        );

        # 3. Special cases (Substitutions)

        # ren (Python) - Needs library paths
        renTpl = builtins.readFile (scriptsDir + "/ren");
        renText = lib.replaceStrings ["@LIBPP@" "@LIBCOLORED@"] [libpp libcolored] renTpl;

        # vid-info.py (Python) - Needs library paths.
        # Note: Original config mapped it to .local/bin/vid-info (without .py)
        vidInfoTpl = builtins.readFile (scriptsDir + "/vid-info.py");
        vidInfoText = lib.replaceStrings ["@LIBPP@" "@LIBCOLORED@"] [libpp libcolored] vidInfoTpl;

        # 4. New scripts (pypr-run, mount-drive)
        # These are now in modules/user/nix-maid/scripts/

        # pypr-run: Use the robust wrapper which handles the hyprland socket signature
        # We need to substitute the 'pypr' executable path into it if we want it to be pure,
        # but the script uses `exec pypr "$@"`, assuming pypr is in PATH.
        # Let's check the script content I wrote.
        # I wrote: `exec pypr "$@"` in pypr-run.
        # Ideally we should make it robust by substituting the path.
        pyprExe = lib.getExe' pkgs.pyprland "pypr";
        pyprRunTpl = builtins.readFile ./scripts/pypr-run;
        pyprRunText = lib.replaceStrings ["exec pypr"] ["exec ${pyprExe}"] pyprRunTpl;

        # mount-drive: Uses rclone. I wrote the script to rely on `command -v rclone`.
        # We can substitute it to be safer.
        rcloneExe = lib.getExe pkgs.rclone;
        mountDriveTpl = builtins.readFile ./scripts/mount-drive;
        mountDriveText = lib.replaceStrings ["rclone mount"] ["${rcloneExe} mount"] mountDriveTpl;
      in
        autoEntries
        // scriptEntries
        // {
          ".local/bin/ren" = {
            executable = true;
            text = renText;
          };
          ".local/bin/vid-info" = {
            executable = true;
            text = vidInfoText;
          };
          ".local/bin/pypr-run" = {
            executable = true;
            text = pyprRunText;
          };
          ".local/bin/mount-drive" = {
            executable = true;
            text = mountDriveText;
          };
        };
    }
  ])
