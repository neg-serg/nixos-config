{
  lib,
  config,
  pkgs,
  neg,
  impurity ? null,
  ...
}:
let
  n = neg impurity;
in
{
  config = lib.mkIf (config.features.gui.enable or false) (
    n.mkHomeFiles (
      let
        # Path to the source directories
        binDir = ../../../../packages/local-bin/bin;
        scriptsDir = ../../../../packages/local-bin/scripts;
        appsDir = ../../../../packages/local-bin/share/applications;

        # Python library paths for special scripts
        sp = pkgs.python3.sitePackages; # High-level dynamically-typed programming language
        libpp = "${pkgs.neg.pretty_printer}/${sp}";
        libcolored = "${pkgs.python3Packages.colored}/${sp}";

        # 1. Scripts from packages/local-bin/bin
        # We filter for regular files.
        binFiles =
          if builtins.pathExists binDir then
            lib.filterAttrs (_: v: v == "regular") (builtins.readDir binDir)
          else
            { };

        # Scripts to skip automatic generation for (handled specially below)
        autoSkip = [
          "ren"
          "kitty-scrollback-nvim"
        ];

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
        scriptFiles =
          if builtins.pathExists scriptsDir then
            lib.filterAttrs (_: v: v == "regular") (builtins.readDir scriptsDir)
          else
            { };

        scriptSkip = [
          "ren"
          "vid-info.py"
        ]; # These need substitution

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

        # 3. Desktop files from packages/local-bin/share/applications
        appsFiles =
          if builtins.pathExists appsDir then
            lib.filterAttrs (_: v: v == "regular") (builtins.readDir appsDir)
          else
            { };

        mkAppAuto = name: {
          name = ".local/share/applications/${name}";
          value = {
            text = builtins.readFile (appsDir + "/${name}");
          };
        };

        appsEntries = builtins.listToAttrs (map mkAppAuto (builtins.attrNames appsFiles));

        # 4. Special cases (Substitutions)

        # ren (Python) - Needs library paths
        renTpl = builtins.readFile (scriptsDir + "/ren");
        renText = lib.replaceStrings [ "@LIBPP@" "@LIBCOLORED@" ] [ libpp libcolored ] renTpl;

        # vid-info.py (Python) - Needs library paths.
        vidInfoTpl = builtins.readFile (scriptsDir + "/vid-info.py");
        vidInfoText = lib.replaceStrings [ "@LIBPP@" "@LIBCOLORED@" ] [ libpp libcolored ] vidInfoTpl;

        # 4. New scripts (pypr-run, mount-drive)
        # These are now in modules/user/nix-maid/scripts/

        # pypr-run: Use the robust wrapper which handles the hyprland socket signature
        pyprExe = lib.getExe' pkgs.pyprland_fixed "pypr";
        pyprRunTpl = builtins.readFile ../scripts/pypr-run;
        pyprRunText = lib.replaceStrings [ "exec pypr" ] [ "exec ${pyprExe}" ] pyprRunTpl;

        # mount-drive: Uses rclone.
        rcloneExe = lib.getExe pkgs.rclone; # Command line program to sync files and directories to and...
        mountDriveTpl = builtins.readFile ../scripts/mount-drive;
        mountDriveText = lib.replaceStrings [ "rclone mount" ] [ "${rcloneExe} mount" ] mountDriveTpl;

        # kitty-scrollback-nvim substitution
        nixKsbPath = "${pkgs.vimPlugins.kitty-scrollback-nvim}/python/kitty_scrollback_nvim.py";
        ksbTpl = builtins.readFile (binDir + "/kitty-scrollback-nvim");
        ksbText = lib.replaceStrings [ "@NIX_KSB_PATH@" ] [ nixKsbPath ] ksbTpl;
      in
      autoEntries
      // scriptEntries
      // appsEntries
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
        ".local/bin/kitty-scrollback-nvim" = {
          executable = true;
          text = ksbText;
        };
      }
    )
  );
}
