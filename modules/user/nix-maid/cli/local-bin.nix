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
        # Data files of the local-bin tools (the window-class table of
        # menu-search, see raise_window_for there) — these are configuration,
        # not scripts, so they live under files/ and are rendered verbatim.
        filesDir = config.lib.neg.path "files/menu-search";

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
          # docling (drives the pdf2md wrapper): the CLI ships inside a python
          # env, not as a top-level attribute — pin that env's bin/docling here.
          # Same env as modules/cli/ocr.nix, with the docling/docling-slim
          # bin/docling-tools collision ignored there (see the note on
          # doclingEnv); the two expressions must stay identical so both sites
          # resolve to one store path.
          "@DOCLING_BIN@" = "${
            (pkgs.python3.withPackages (ps: [ ps.docling ])).overrideAttrs (_: {
              ignoreCollisions = true;
            })
          }/bin/docling";
          # The music-AI venv tree lives outside the repo; the scripts used to
          # spell the path out 19 times. Rendered output is unchanged (the
          # substitution is the same string), so this only moves the one place
          # that has to know where the tree sits.
          "@MUSIC_AI_BASE@" = "/zero/ai/music-ai";
          # Music tagging/embedding wrappers (music-embed, music-tags,
          # music-index, music-similar, audio-analysis): a nix python is the
          # interpreter, the venv contributes site-packages over PYTHONPATH,
          # and the payloads are a store copy of packages/local-bin/lib. Both
          # store paths ride in the system closure, so nix-collect-garbage
          # cannot break these tools the way it broke the venvs' own
          # bin/python symlinks (2026-10-10, see scripts/dev/fix-music-venvs.sh).
          "@MUSIC_AI_PY@" = "${pkgs.python312}/bin/python3.12";
          "@MUSIC_AI_LIB@" = "${config.lib.neg.path "packages/local-bin/lib"}";
          "@MUSIC_AI_HF_HOME@" = config.features.media.audio.musicTagging.hfHome;
          "@MUSIC_EMBED_MODEL@" = config.features.media.audio.musicTagging.embedModel;
          # Trained MTG tagger (music-mtg-tags): its own venv, because
          # venv-analysis carries a plain essentia without the
          # TensorflowPredict* classes, plus the pinned model directory.
          "@MUSIC_MTG_VENV@" = config.features.media.audio.musicTagging.mtgVenv;
          "@MUSIC_MTG_MODELS@" = config.features.media.audio.musicTagging.mtgModels;
          # Music Flamingo 8B audio LLM behind music-describe: model id (or a
          # local directory) and the device the wrapper defaults to.
          "@MUSIC_DESCRIBE_MODEL@" = config.features.media.audio.musicTagging.describeModel;
          "@MUSIC_DESCRIBE_DEVICE@" = config.features.media.audio.musicTagging.describeDevice;
          "@MUSIC_DESCRIBE_ENGINE@" = config.features.media.audio.musicTagging.describeEngine;
          "@MUSIC_AFNEXT_MODEL@" = config.features.media.audio.musicTagging.describeGpuModel;
        };
        subst = lib.replaceStrings (builtins.attrNames substs) (builtins.attrValues substs);

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
          "glm-midi-relay"
          "surfingkeys-server"
          "window-activate"
          "paths"
          "menu-search"
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

        # kitty-scrollback-nvim substitution
        nixKsbPath = "${pkgs.vimPlugins.kitty-scrollback-nvim}/python/kitty_scrollback_nvim.py";
        ksbTpl = subst (builtins.readFile (binDir + "/kitty-scrollback-nvim"));
        ksbText = lib.replaceStrings [ "@NIX_KSB_PATH@" ] [ nixKsbPath ] ksbTpl;
      in
      autoEntries
      // scriptEntries
      // {
        # Rust port (packages/local-bin-tools): no interpreter, no PYTHONPATH.
        ".local/bin/ren".source = lib.getExe' pkgs.neg.local-bin-tools "ren";
        # Rust port (packages/pretty-printer): no interpreter, no PYTHONPATH.
        ".local/bin/vid-info".source = lib.getExe' pkgs.neg.pretty_printer "vid-info";
        # Rust ports of two former scripts (packages/local-bin-tools).
        ".local/bin/menu-search".source = lib.getExe' pkgs.neg.local-bin-tools "menu-search";
        ".local/bin/paths".source = lib.getExe' pkgs.neg.local-bin-tools "paths";
        ".local/bin/window-activate".source = lib.getExe' pkgs.neg.local-bin-tools "window-activate";
        ".local/bin/surfingkeys-server".source = lib.getExe' pkgs.neg.local-bin-tools "surfingkeys-server";
        ".local/bin/glm-midi-relay".source = lib.getExe' pkgs.neg.local-bin-tools "glm-midi-relay";
        ".local/bin/fetch-covers".source = lib.getExe' pkgs.neg.local-bin-tools "fetch-covers";
        ".local/bin/gen-unbound-hosts".source = lib.getExe' pkgs.neg.local-bin-tools "gen-unbound-hosts";
        ".local/bin/kitty-scrollback-nvim" = {
          executable = true;
          text = ksbText;
        };
        ".local/bin/hypr-focus-hist" = {
          executable = true;
          source = "${pkgs.neg.hypr-focus}/bin/hypr-focus";
        };
        # menu-search reads it to match a tray entry to its window (the id in the
        # tray registry vs. the window class); deleting the file only costs the
        # fallback to the heuristic match, it is not an error.
        ".config/menu-search/window-class.tsv" = {
          text = builtins.readFile (filesDir + "/window-class.tsv");
        };
        # Shader sources that ship with the shtoy helper — the self-contained
        # ports in files/gui/shtoy (ltffzl, mtyGWy) plus their default textures.
        # Imported shadertoy.com sources stay in ~/.cache/shtoy instead.
        ".config/shtoy/shaders" = {
          source = config.lib.neg.path "files/gui/shtoy/shaders";
        };
        ".config/shtoy/tex" = {
          source = config.lib.neg.path "files/gui/shtoy/tex";
        };
      }
    )
  );
}
