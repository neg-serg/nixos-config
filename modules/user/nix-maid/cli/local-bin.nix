{
  lib,
  config,
  pkgs,
  neg,
  ...
}:
{
  config = lib.mkIf (config.lib.neg.enabled "gui") (
    neg.mkHomeFiles (
      let
        # Path to the source directories
        binDir = config.lib.neg.path "packages/local-bin/bin";
        scriptsDir = config.lib.neg.path "packages/local-bin/scripts";

        # Shared runtime library dirs for the music-AI scripts. Twenty of them
        # used to carry literal /nix/store paths for these libs: the copies went
        # stale on the next nixpkgs bump and fell out of the system closure (the
        # gcc one had no gc root left at all), so a `nix-collect-garbage -d`
        # silently broke every script. Substituting them here keeps one source
        # of truth and puts the paths into the derivation's string context, so
        # the store keeps them alive.
        libDirSubsts = {
          "@GCC_LIB_DIR@" = "${pkgs.gcc.cc.lib}/lib"; # libstdc++/libgomp for the torch wheels
          "@ZLIB_LIB_DIR@" = "${pkgs.zlib}/lib"; # libz
          "@ZSTD_LIB_DIR@" = "${pkgs.zstd.out}/lib"; # libzstd (torch >= 2.13 links it)
        };
        substLibDirs = lib.replaceStrings (builtins.attrNames libDirSubsts) (
          builtins.attrValues libDirSubsts
        );

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
          "kitty-scrollback-nvim"
        ];

        # Helper to generate the home.file entry
        mkAuto = name: {
          name = ".local/bin/${name}";
          value = {
            executable = true;
            text = substLibDirs (builtins.readFile (binDir + "/${name}"));
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
            text = substLibDirs (builtins.readFile (scriptsDir + "/${name}"));
          };
        };

        scriptEntries =
          builtins.attrNames scriptFiles
          |> lib.filter (n: !(lib.elem n scriptSkip))
          |> map mkScriptAuto
          |> builtins.listToAttrs;

        # 3. Special cases (Substitutions)

        # ren (Python) - Needs library paths
        renTpl = substLibDirs (builtins.readFile (scriptsDir + "/ren"));
        renText = lib.replaceStrings [ "@LIBPP@" "@LIBCOLORED@" ] [ libpp libcolored ] renTpl;

        # vid-info.py (Python) - Needs library paths.
        vidInfoTpl = substLibDirs (builtins.readFile (scriptsDir + "/vid-info.py"));
        vidInfoText = lib.replaceStrings [ "@LIBPP@" "@LIBCOLORED@" ] [ libpp libcolored ] vidInfoTpl;

        # kitty-scrollback-nvim substitution
        nixKsbPath = "${pkgs.vimPlugins.kitty-scrollback-nvim}/python/kitty_scrollback_nvim.py";
        ksbTpl = substLibDirs (builtins.readFile (binDir + "/kitty-scrollback-nvim"));
        ksbText = lib.replaceStrings [ "@NIX_KSB_PATH@" ] [ nixKsbPath ] ksbTpl;
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
