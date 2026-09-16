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

        # Substitution table for the local-bin scripts. The runtime library dirs
        # used to be literal /nix/store paths copied into twenty scripts: the
        # copies went stale on the next nixpkgs bump and fell out of the system
        # closure (the gcc one had no gc root left at all), so a
        # `nix-collect-garbage -d` silently broke every script. Keeping them here
        # means one source of truth, plus a string context that pins the store
        # paths to whatever consumes the rendered file.
        substs = {
          "@GCC_LIB_DIR@" = "${pkgs.gcc.cc.lib}/lib"; # libstdc++/libgomp for the torch wheels
          "@ZLIB_LIB_DIR@" = "${pkgs.zlib}/lib"; # libz
          "@ZSTD_LIB_DIR@" = "${pkgs.zstd.out}/lib"; # libzstd (torch >= 2.13 links it)
          # marker falls back to this when llama-server is not in PATH; the
          # literal it used to carry (llama-cpp-9190) is gone from the store.
          "@LLAMA_SERVER_BIN@" = "${pkgs.llama-cpp-vulkan}/bin/llama-server";
          # The music-AI venv tree lives outside the repo; the scripts used to
          # spell the path out 19 times. Rendered output is unchanged (the
          # substitution is the same string), so this only moves the one place
          # that has to know where the tree sits.
          "@MUSIC_AI_BASE@" = "/zero/ai/music-ai";
        };
        subst = lib.replaceStrings (builtins.attrNames substs) (builtins.attrValues substs);

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

        autoEntries =
          neg.mkDirEntries ".local/bin"
            (builtins.attrNames binFiles |> lib.filter (n: !(lib.elem n autoSkip)))
            (name: {
              executable = true;
              text = subst (builtins.readFile (binDir + "/${name}"));
            });

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

        scriptEntries =
          neg.mkDirEntries ".local/bin"
            (builtins.attrNames scriptFiles |> lib.filter (n: !(lib.elem n scriptSkip)))
            (name: {
              executable = true;
              text = subst (builtins.readFile (scriptsDir + "/${name}"));
            });

        # 3. Special cases (Substitutions)

        # ren (Python) - Needs library paths
        renTpl = subst (builtins.readFile (scriptsDir + "/ren"));
        renText = lib.replaceStrings [ "@LIBPP@" "@LIBCOLORED@" ] [ libpp libcolored ] renTpl;

        # vid-info.py (Python) - Needs library paths.
        vidInfoTpl = subst (builtins.readFile (scriptsDir + "/vid-info.py"));
        vidInfoText = lib.replaceStrings [ "@LIBPP@" "@LIBCOLORED@" ] [ libpp libcolored ] vidInfoTpl;

        # kitty-scrollback-nvim substitution
        nixKsbPath = "${pkgs.vimPlugins.kitty-scrollback-nvim}/python/kitty_scrollback_nvim.py";
        ksbTpl = subst (builtins.readFile (binDir + "/kitty-scrollback-nvim"));
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
