{
  lib,
  config,
  pkgs,
  neg,
  ...
}:
let
  n = neg;
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
            builtins.readDir binDir |> lib.filterAttrs (_: v: v == "regular")
          else
            { };

        # Scripts to skip automatic generation for (handled specially below)
        autoSkip = [
          "ren"
          "kitty-scrollback-nvim"
          "hypr-focus-hist"
        ];

        # Helper to generate the home.file entry
        mkAuto = name: {
          name = ".local/bin/${name}";
          value = {
            executable = true;
            text = builtins.readFile (binDir + "/${name}");
          };
        };

        autoEntries =
          builtins.attrNames binFiles
          |> lib.filter (n: !(lib.elem n autoSkip))
          |> map mkAuto
          |> builtins.listToAttrs;

        # 2. Scripts from packages/local-bin/scripts
        scriptFiles =
          if builtins.pathExists scriptsDir then
            builtins.readDir scriptsDir |> lib.filterAttrs (_: v: v == "regular")
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

        scriptEntries =
          builtins.attrNames scriptFiles
          |> lib.filter (n: !(lib.elem n scriptSkip))
          |> map mkScriptAuto
          |> builtins.listToAttrs;

        # 3. Desktop files from packages/local-bin/share/applications
        appsFiles =
          if builtins.pathExists appsDir then
            builtins.readDir appsDir |> lib.filterAttrs (_: v: v == "regular")
          else
            { };

        mkAppAuto = name: {
          name = ".local/share/applications/${name}";
          value = {
            text = builtins.readFile (appsDir + "/${name}");
          };
        };

        appsEntries = builtins.attrNames appsFiles |> map mkAppAuto |> builtins.listToAttrs;

        # 4. Special cases (Substitutions)

        # ren (Python) - Needs library paths
        renTpl = builtins.readFile (scriptsDir + "/ren");
        renText = lib.replaceStrings [ "@LIBPP@" "@LIBCOLORED@" ] [ libpp libcolored ] renTpl;

        # vid-info.py (Python) - Needs library paths.
        vidInfoTpl = builtins.readFile (scriptsDir + "/vid-info.py");
        vidInfoText = lib.replaceStrings [ "@LIBPP@" "@LIBCOLORED@" ] [ libpp libcolored ] vidInfoTpl;

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
        ".local/bin/kitty-scrollback-nvim" = {
          executable = true;
          text = ksbText;
        };
        ".local/bin/hypr-focus-hist" = {
          executable = true;
          source = "${pkgs.neg.hypr-focus}/bin/hypr-focus";
        };
      }
    )
  );
}
