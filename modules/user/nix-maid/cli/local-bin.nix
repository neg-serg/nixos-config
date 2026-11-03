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
          # The music-AI venv tree lives outside the repo; the scripts used to
          # spell the path out 19 times. Rendered output is unchanged (the
          # substitution is the same string), so this only moves the one place
          # that has to know where the tree sits.
          "@MUSIC_AI_BASE@" = "/zero/ai/music-ai";
          # Music tagging/embedding wrappers (music-embed, music-tags,
          # audio-analysis): a nix python is the
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
          "surfingkeys-server"
          "window-activate"
          "paths"
          "menu-search"
          "dsh-worktree"
          "shtoy"
          "proxy"
          "swayimg-actions.sh"
          "steam-cloud-fix"
          "dsh-statusline"
          "sw"
          "shade"
          "main-menu"
          "surfingkeys-extension-patch"
          "dsh-url"
          "qr"
          "pdf2md"
          "upstream-radar"
          "vsmlrt-models"
          "nix-updates"
          "audio-diag"
          "jam"
          "shabda"
          "synth"
          "midi-bridge"
          "renoise-osc-config"
          "sc-live"
          "sc-record"
          "flacspec"
          "mp"
          "nb"
          "qe"
          "pic-notify"
          "screenrec"
          "clip"
          "screenshot-toast"
          "pic-info"
          "pic-ocr"
          "pic-dirs-list"
          "wl-restore"
          "unlock"
          "kitty-font-zoom"
          "cursor-stretch"
          "pngoptim"
          "hypr-resize-proportional"
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
          "pass-2col"
          "punzip"
          "tty-log"
          "journal-clean.sh"
          "music-highlevel"
        ]; # substitution or Rust ports

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
        ".local/bin/fetch-covers".source = lib.getExe' pkgs.neg.local-bin-tools "fetch-covers";
        # Rust ports of the remaining scripts/ helpers (packages/local-bin-scripts).
        ".local/bin/pass-2col".source = lib.getExe' pkgs.neg.local-bin-scripts "pass-2col";
        ".local/bin/punzip".source = lib.getExe' pkgs.neg.local-bin-scripts "punzip";
        ".local/bin/tty-log".source = lib.getExe' pkgs.neg.local-bin-scripts "tty-log";
        ".local/bin/journal-clean.sh".source = lib.getExe' pkgs.neg.local-bin-scripts "journal-clean";
        ".local/bin/music-highlevel".source = lib.getExe' pkgs.neg.local-bin-scripts "music-highlevel";
        # Rust ports of the system-level helpers (packages/local-bin-system).
        ".local/bin/steam-cloud-fix".source = lib.getExe' pkgs.neg.local-bin-system "steam-cloud-fix";
        ".local/bin/dsh-statusline".source = lib.getExe' pkgs.neg.local-bin-system "dsh-statusline";
        ".local/bin/sw".source = lib.getExe' pkgs.neg.local-bin-system "sw";
        ".local/bin/shade".source = lib.getExe' pkgs.neg.local-bin-system "shade";
        ".local/bin/main-menu".source = lib.getExe' pkgs.neg.local-bin-system "main-menu";
        ".local/bin/surfingkeys-extension-patch".source =
          lib.getExe' pkgs.neg.local-bin-system "surfingkeys-extension-patch";
        ".local/bin/dsh-url".source = lib.getExe' pkgs.neg.local-bin-system "dsh-url";
        ".local/bin/qr".source = lib.getExe' pkgs.neg.local-bin-system "qr";
        ".local/bin/pdf2md".source = lib.getExe' pkgs.neg.local-bin-system "pdf2md";
        ".local/bin/upstream-radar".source = lib.getExe' pkgs.neg.local-bin-system "upstream-radar";
        ".local/bin/vsmlrt-models".source = lib.getExe' pkgs.neg.local-bin-system "vsmlrt-models";
        ".local/bin/nix-updates".source = lib.getExe' pkgs.neg.local-bin-system "nix-updates";
        # Rust ports of the audio helpers (packages/local-bin-audio).
        ".local/bin/audio-diag".source = lib.getExe' pkgs.neg.local-bin-audio "audio-diag";
        ".local/bin/jam".source = lib.getExe' pkgs.neg.local-bin-audio "jam";
        ".local/bin/shabda".source = lib.getExe' pkgs.neg.local-bin-audio "shabda";
        ".local/bin/synth".source = lib.getExe' pkgs.neg.local-bin-audio "synth";
        ".local/bin/midi-bridge".source = lib.getExe' pkgs.neg.local-bin-audio "midi-bridge";
        ".local/bin/renoise-osc-config".source = lib.getExe' pkgs.neg.local-bin-audio "renoise-osc-config";
        ".local/bin/sc-live".source = lib.getExe' pkgs.neg.local-bin-audio "sc-live";
        ".local/bin/sc-record".source = lib.getExe' pkgs.neg.local-bin-audio "sc-record";
        ".local/bin/flacspec".source = lib.getExe' pkgs.neg.local-bin-audio "flacspec";
        ".local/bin/mp".source = lib.getExe' pkgs.neg.local-bin-audio "mp";
        ".local/bin/nb".source = lib.getExe' pkgs.neg.local-bin-audio "nb";
        ".local/bin/qe".source = lib.getExe' pkgs.neg.local-bin-audio "qe";

        # Rust ports of the desktop/media helpers (packages/local-bin-desktop).
        ".local/bin/pic-notify".source = lib.getExe' pkgs.neg.local-bin-desktop "pic-notify";
        ".local/bin/screenrec".source = lib.getExe' pkgs.neg.local-bin-desktop "screenrec";
        ".local/bin/clip".source = lib.getExe' pkgs.neg.local-bin-desktop "clip";
        ".local/bin/screenshot-toast".source = lib.getExe' pkgs.neg.local-bin-desktop "screenshot-toast";
        ".local/bin/pic-info".source = lib.getExe' pkgs.neg.local-bin-desktop "pic-info";
        ".local/bin/pic-ocr".source = lib.getExe' pkgs.neg.local-bin-desktop "pic-ocr";
        ".local/bin/pic-dirs-list".source = lib.getExe' pkgs.neg.local-bin-desktop "pic-dirs-list";
        ".local/bin/wl-restore".source = lib.getExe' pkgs.neg.local-bin-desktop "wl-restore";
        ".local/bin/unlock".source = lib.getExe' pkgs.neg.local-bin-desktop "unlock";
        ".local/bin/kitty-font-zoom".source = lib.getExe' pkgs.neg.local-bin-desktop "kitty-font-zoom";
        ".local/bin/cursor-stretch".source = lib.getExe' pkgs.neg.local-bin-desktop "cursor-stretch";
        ".local/bin/pngoptim".source = lib.getExe' pkgs.neg.local-bin-desktop "pngoptim";
        ".local/bin/hypr-resize-proportional".source =
          lib.getExe' pkgs.neg.local-bin-desktop "hypr-resize-proportional";

        # Rust port of the former shell helper (packages/local-bin-tools).
        ".local/bin/dsh-worktree".source = lib.getExe' pkgs.neg.local-bin-tools "dsh-worktree";
        # Rust port of the former shell helper (packages/shtoy).
        ".local/bin/shtoy".source = lib.getExe' pkgs.neg.shtoy "shtoy";
        # Rust port of the former shell helper (packages/sing-box-proxy).
        ".local/bin/proxy".source = lib.getExe' pkgs.neg.sing-box-proxy "proxy";
        # Rust port of the former shell helper (packages/swayimg-actions).
        # The .sh name is kept: files/gui/swayimg/init.lua execs that path.
        ".local/bin/swayimg-actions.sh".source = lib.getExe' pkgs.neg.swayimg-actions "swayimg-actions";
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
