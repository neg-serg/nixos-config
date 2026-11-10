#
# Custom packages and vendored sources
# (moved out of the docs tree; keep it in sync with the code it describes)
#
#
# - All local derivations (`pkgs.neg.*`, CLI wrappers, MCP servers, etc.) now live under the top-level
#   `packages/` directory.
# - The overlay is applied in `flake/lib.nix` (`mkPkgs`); flake outputs for the custom packages are
#   exposed via `packages/flake/custom-packages.nix` (e.g. `nix build .#omp`).
# - Vendored sources live in `files/sources/` and are referenced as relative path literals (see the
#   header of `packages/overlays/vendored-sources.nix`). Files above GitHub's 100 MB limit cannot be
#   committed, so the licensed Renoise/Redux installers sit outside the repository under
#   `$XDG_DATA_HOME/nixos-src/renoise` (`/home/neg/.local/share/nixos-src/renoise` on trantor) and
#   arrive as the `renoise-src` path input (`flake.nix`, `flake = false`), consumed as
#   `inputs.renoise-src + "/<tarball>"`. Two consequences: a clone without that directory fails to
#   evaluate `renoise`/`renoise-redux`, and relocating such a file inside the tree does not help —
#   the flake source contains tracked files only, and absolute paths are rejected in pure
#   evaluation.

inputs: final: finalPrev:
let
  # Repo-root resolver (lib/neg-helpers.nix `rooted`): a package or overlay in
  # this tree reaches a repo file as `paths.path "files/sources/x.tar.gz"`
  # instead of counting `./../../` levels. Handed to every overlay that needs it
  # through importOvP below, and to package files by neg.functions.callPkg.
  # The resolver itself needs the root, so this is the one place in packages/
  # that spells it out.
  # allow-relative: the bootstrap line.
  paths = (import ../lib/neg-helpers.nix).rooted ../.;

  importOv = path: import path inputs final finalPrev;
  importOvP = path: import path { inherit inputs paths; } final finalPrev;
  functions = importOvP ./overlays/functions.nix;
  tools = importOvP ./overlays/tools.nix;
  media = importOv ./overlays/media.nix;
  gui = importOv ./overlays/gui.nix;
  dev = importOv ./overlays/dev.nix;
  fixTinycc = importOv ./overlays/fix-tinycc.nix;
  trim = importOv ./overlays/trim.nix;
  fixSources = importOv ./overlays/fix-sources.nix;
  aurPorted = import ./overlays/aur-ported.nix final finalPrev;
  vendored = importOvP ./overlays/vendored-sources.nix;

  # Rust slimming: see packages/rust-slim.nix for the two measured levers.
  # The name lists are the single place that knows which packages are Rust —
  # `neg` names live under pkgs.neg, `top` names are the top-level attributes
  # the chunk overlays define (elio/graf/huebox/lazytail are defined below and
  # wrapped at their definition instead).
  rustSlim = import ./rust-slim.nix;
  rustNegNames = [
    "aurora"
    "aurora-tools"
    "blizzard"
    "dnsglobe"
    "dsh-patch"
    "game"
    "hwctl"
    "hypr-focus"
    "hypr-rearrange"
    "hypr-win-list"
    "lazytail"
    "local-bin-audio"
    "local-bin-desktop"
    "local-bin-misc"
    "local-bin-scripts"
    "local-bin-system"
    "local-bin-tools"
    "local-bin-zsh"
    "local-bin-zsh-extra"
    "minibbs"
    "music-apply-tags"
    "music-index-tools"
    "nixbuild-status"
    "pleamar-calendar"
    "pleamar-fixtures"
    "pleamar-harness"
    "pleamar-journal"
    "pleamar-kbdlayout"
    "pleamar-picker"
    "pleamar-sysmon"
    "pleamar-theme"
    "pleamar-weather"
    "questyle-ctl"
    "renoise-osc"
    "scratchpad-geometry"
    "shtoy"
    "sing-box-proxy"
    "swayimg-actions"
    "telegram-notify"
    "tgchat-rs"
    "tidalctl"
    "tint"
    "topowall"
    "vivaldi-prefs"
    "wallpaper-palettes"
    "wineapps"
    "zalgo"
  ];
  rustTopNames = [
    "craft-anything"
    "deckcraft"
    "figcraft"
    "genlc"
    "gridcraft"
    "mpd-voice"
    "nixie"
    "pw-audioshare"
    "pwroute"
    "solidcraft"
    "sonda"
    "soundcraft"
    "tint"
    "vectorcraft"
    "wl"
    "wordcraft"
    "zalgo"
  ];
  chunks =
    functions
    // tools
    // media
    // dev
    // gui
    // fixTinycc
    // trim
    // fixSources
    // aurPorted
    // vendored
    // disableChecks;
  slimChunks =
    chunks
    // builtins.listToAttrs (
      map (n: {
        name = n;
        value = rustSlim chunks.${n};
      }) rustTopNames
    );

  # WARNING: disableChecks MUST be last in the merge chain (//) below.
  # It calls overrideAttrs which resets any prior overrides on the same package.
  disableChecks = import ./overlays/disable-checks.nix inputs final finalPrev;
in
# Standard overlay pattern: merge top-level attributes
slimChunks
// {

  # vcv-rack's Makefile declares no dependency between the plugin sub-make
  # and libRack.so, but nixpkgs passes "all plugins" to one parallel make —
  # the plugin link can read libRack.so mid-write and fail with
  # "file format not recognized" (flaky). Build `all` first, then plugins in
  # postBuild (the same split nixpkgs already uses for the Darwin dist target).
  vcv-rack = finalPrev.vcv-rack.overrideAttrs (old: {
    makeFlags = builtins.filter (flag: flag != "plugins") (old.makeFlags or [ ]);
    postBuild =
      (old.postBuild or "")
      + finalPrev.lib.optionalString (!finalPrev.stdenv.hostPlatform.isDarwin) ''
        make plugins
      '';
  });

  # Host firmware subset for trantor; replaces the full linux-firmware bundle.
  linux-firmware-minimal = final.callPackage ./linux-firmware-minimal { };

  # GHCi with the TidalCycles library preloaded — used by the nvim tidal
  # ftplugin (tidal-edit / tidalctl demo/code) to boot a tidal> REPL.
  tidal-ghci = final.writeShellScriptBin "tidal-ghci" ''
    exec ${final.ghc.withPackages (ps: [ ps.tidal ])}/bin/ghci "$@"
  '';

  # Merge all pkgs.neg sub-attributes from individual overlays, then slim the
  # Rust ones (packages/rust-slim.nix).
  neg =
    let
      base =
        (functions.neg or { })
        // (tools.neg or { })
        // (media.neg or { })
        // (dev.neg or { })
        // (gui.neg or { })
        // {
          game = final.callPackage ./game { }; # Unified game launcher
          joern = final.callPackage ./joern { }; # Open-source code analysis platform
          superdirt = final.callPackage ./superdirt { }; # SuperDirt SC quark for TidalCycles audio engine
          superdirt-mixer = final.callPackage ./superdirt-mixer { }; # graphical mixer UI quark for SuperDirt orbits (gain/pan/reverb/EQ/compressor)
          equi = final.callPackage ./equi { inherit (final.neg.functions) mkScQuark; }; # EQui SC quark (parametric EQ) — SuperDirtMixer dependency
          jsonlib = final.callPackage ./jsonlib { inherit (final.neg.functions) mkScQuark; }; # JSONlib SC quark (JSON en/decoder) — SuperDirtMixer dependency
          dwg-reverb = final.callPackage ./dwg-reverb { }; # compiled SC UGen plugin: virtual room reverb (early reflections + FDN late reverb)
          dirt-samples = final.callPackage ./dirt-samples { }; # audio sample library for SuperDirt
          vowel = final.callPackage ./vowel { inherit (final.neg.functions) mkScQuark; }; # Vowel SC quark (formant tables) used by SuperDirt
          dsh-patch = final.callPackage ./dsh-patch { }; # count-asserted patcher for dsh bundles and profiles
          dsh = final.callPackage ./dsh { inherit (final.neg) dsh-patch; }; # DeepSeek Harness agent CLI (dsh)
          natshell = final.callPackage ./natshell { }; # natural-language shell agent TUI (remote inference via llama-swap)
          aurora = final.callPackage ./aurora.nix {
            src = inputs.aurora-src;
          }; # aurora: local MPD player with a Vulkan UI
          aurora-tools = final.callPackage ./aurora.nix {
            src = inputs.aurora-src;
            toolsOnly = true;
          }; # aurora-tools: the headphone model catalogue CLI, without the player's Vulkan closure
          renoise-redux = final.callPackage ./renoise-redux {
            renoiseSrc = inputs.renoise-src;
          }; # Renoise Redux VST3 plugin (licensed build)
          protoplug = final.callPackage ./protoplug { }; # Lua live-coding VST2 plugins (Fx + Gen, MIT)
          midi-transcribe = final.callPackage ./midi-transcribe { }; # audio->MIDI transcription via Sony hFT-Transformer (CPU)
          virtual-midi = final.callPackage ./virtual-midi { }; # user-space virtual ALSA seq MIDI ports (synth slots)
          questyle-ctl = final.callPackage ./questyle-ctl { }; # USB/ALSA/PipeWire + vendor HID channel of the Questyle QCC dongle
          pleamar-fixtures = final.callPackage ./pleamar-fixtures { }; # D-Bus fixtures for the pleamar engine (MPRIS player, nested tray item)
          pleamar-sysmon = final.callPackage ./pleamar-sysmon { }; # pleamar system monitor worker (procfs/sysfs, JSON lines)
          pleamar-weather = final.callPackage ./pleamar-weather { }; # pleamar weather worker (Open-Meteo/MET Norway/wttr.in, JSON lines)
          pleamar-kbdlayout = final.callPackage ./pleamar-kbdlayout { }; # pleamar keyboard-layout worker (hyprctl, JSON lines)
          pleamar-journal = final.callPackage ./pleamar-journal { }; # pleamar journal snapshot command (journalctl, one JSON line)
          pleamar-theme = final.callPackage ./pleamar-theme { }; # pleamar theme pipeline (wallpaper colours -> theme.plm)
          pleamar-calendar = final.callPackage ./pleamar-calendar { }; # pleamar calendar worker (khal, holidays, production calendar, JSON lines)
          pleamar-picker = final.callPackage ./pleamar-picker { }; # picker scene commands (wallpaper still/apply, deck CLI)
          pleamar-harness = final.callPackage ./pleamar-harness { }; # pleamar developer harnesses (measure, describe-snap, smoke) as Rust binaries
          local-bin-scripts = final.callPackage ./local-bin-scripts { }; # Rust ports of the small local-bin helper scripts
          local-bin-desktop = final.callPackage ./local-bin-desktop { }; # Rust ports of the desktop/media local-bin helpers
          local-bin-audio = final.callPackage ./local-bin-audio { }; # Rust ports of the audio helpers (audio-diag, jam, sc-live, ...)
          local-bin-misc = final.callPackage ./local-bin-misc { }; # Rust ports of the last local-bin helpers (pb, any, v, pw-jack wrappers)
          local-bin-zsh = final.callPackage ./local-bin-zsh { }; # Rust ports of the last zsh helpers (iommu-info, music-rename, music-tui, pl, read_documents)
          local-bin-zsh-extra = final.callPackage ./local-bin-zsh-extra { }; # Rust ports of gh-issues-export, mpd_del_album, sx, sys-relief, vol, win-vm
          # Docling (~3.9 GiB with its layout/table models): PDF/DOCX → Markdown.
          # Deliberately outside the system closure — it lives in the `ai` devshell
          # and behind the `docling` flake app; pdf2md resolves `docling` from PATH.
          #
          # saxonche is the Schematron backend doclang wants for
          # `doclang validate` without `--xsd-only` (the `schematron-saxon` extra);
          # nixpkgs ships it, so the devshell can validate `.dclx` markup fully.
          #
          # ignoreCollisions: in the pinned nixpkgs (docling 2.118.0) the full
          # package propagates `docling-slim` and BOTH install bin/docling-tools, so
          # buildEnv refuses the environment ("two given paths contain a conflicting
          # subpath", exit 25). The copies are the same version — keep the first.
          docling-env =
            (final.python3.withPackages (ps: [
              ps.docling
              ps.saxonche
            ])).overrideAttrs
              (_: {
                ignoreCollisions = true;
              });
          local-bin-system = final.callPackage ./local-bin-system { }; # Rust ports of the system-level local-bin/bin helpers
          tgchat-rs = final.callPackage ./tgchat-rs { }; # Telegram chat access on a grammers user session (replaces the Python tgchat after a fresh login)
          wineapps = final.callPackage ./wineapps { }; # declarative Wine app manager (list/install/uninstall/run)
          renoise-osc = final.callPackage ./renoise-osc { }; # OSC client for Renoise (remote Lua eval, device/transport control)
          scratchpad-geometry = final.callPackage ./scratchpad-geometry { }; # persist Hyprland scratchpad rects across show/hide
          hypr-rearrange = final.callPackage ./hypr-rearrange { }; # move windows to the workspaces the config routes them to
          hypr-win-list = final.callPackage ./hypr-win-list { }; # Hyprland window picker for vicinae dmenu
          minibbs = final.callPackage ./minibbs { }; # tiny BBS-style message board (SQLite + HTTP)
          telegram-notify = final.callPackage ./telegram-notify { }; # Telegram notifications: calendar digest, pill reminder, crash-loop alerts
          zalgo = final.callPackage ./zalgo { }; # cursed-text generator (combining marks on stdin)
          blizzard = final.callPackage ./blizzard { }; # animated black-metal blizzard WebP generator (fastfetch logos)
          music-apply-tags = final.callPackage ./music-apply-tags { }; # write ML mood/style into audio tags (was scripts/dev/music-apply-tags.py)
          music-index-tools = final.callPackage ./music-index-tools { }; # build/query the MERT similarity index (Rust; embeddings via music-embed)
          vivaldi-prefs = final.callPackage ./vivaldi-prefs { }; # re-assert managed Vivaldi preferences
          wallpaper-palettes = final.callPackage ./wallpaper-palettes { }; # matugen schemes per wallpaper (picker cards)
          local-bin-tools = final.callPackage ./local-bin-tools { }; # small $PATH helpers (fetch-covers, gen-unbound-hosts, menu-search, ren, …)
          shtoy = final.callPackage ./shtoy { }; # run Shadertoy shaders in esshader (Rust port of the local-bin helper)
          sing-box-proxy = final.callPackage ./sing-box-proxy { }; # sing-box proxy controller (Rust port of local-bin/bin/proxy)
          swayimg-actions = final.callPackage ./swayimg-actions { }; # rotate/move/copy/wallpaper/range actions for swayimg (Rust port of the local-bin helper)
        };
    in
    base
    // builtins.listToAttrs (
      map (n: {
        name = n;
        value = rustSlim base.${n};
      }) rustNegNames
    );

  jack-keyboard = final.callPackage ./jack-keyboard { }; # virtual MIDI keyboard for JACK/PipeWire synth hosts

  # tmd-top: real-time per-IP network traffic monitor (TUI) — pinned textual 1.0.0
  # stack on python312, see packages/tmd-top/default.nix
  tmd-top = final.callPackage ./tmd-top { };

  # lazytail: terminal log viewer (ratatui) with live filtering, follow mode and
  # an MCP server — see packages/lazytail/default.nix
  lazytail = rustSlim (final.callPackage ./lazytail { });

  # elio: three-pane terminal file manager (places / files / preview) with inline
  # image previews, archive handling and trash — see packages/elio/default.nix
  elio = rustSlim (final.callPackage ./elio { });

  # tewi: TUI client for Transmission/qBittorrent/Deluge daemons
  # (python app, deps from nixpkgs + local geoip2fast, see packages/tewi/default.nix)
  tewi = final.callPackage ./tewi { };

  # huebox: terminal theme editor (ratatui TUI) — live preview, line-level
  # push of the palette into the terminal config — see packages/huebox/default.nix
  huebox = rustSlim (final.callPackage ./huebox { });

  # graf: terminal force-directed graph of markdown wikilinks (ratatui canvas +
  # fdg-sim physics) — see packages/graf/default.nix
  graf = rustSlim (final.callPackage ./graf { });

  # Code200x Unicode font family by James Kass — Code2000 (BMP), Code2001
  # (Plane 1 ancient scripts), Code2002 (Plane 2 rare CJK), Code20X3 (Plane 3 CJK Ext G/H).
  # One parameterized derivation (packages/ttf-code) with a per-variant table;
  # the public attribute names below are unchanged.
  ttf-code2000 = final.callPackage ./ttf-code { variant = "ttf-code2000"; };
  ttf-code2001 = final.callPackage ./ttf-code { variant = "ttf-code2001"; };
  ttf-code2002 = final.callPackage ./ttf-code { variant = "ttf-code2002"; };
  ttf-code20x3 = final.callPackage ./ttf-code { variant = "ttf-code20x3"; };

  # Python with LTO optimizations
  python3-lto = finalPrev.python3.override {
    packageOverrides = _pythonSelf: _pythonSuper: {
      enableOptimizations = true;
      enableLTO = true;
      reproducibleBuild = false;
    };
  };

  # Fix /sbin/ldconfig symlink in FHS envs (Steam pressure-vessel nested container fix).
  # Symlinking /sbin/ldconfig -> /bin/ldconfig creates a resolution loop when
  # pressure-vessel tries to set up a nested bwrap container for Proton.
  # Copy the binary instead, as SteamRT3 expects.
  buildFHSEnv =
    args:
    finalPrev.buildFHSEnv (
      args
      // {
        extraBuildCommands = (args.extraBuildCommands or "") + ''
          if [ -L $out/usr/sbin/ldconfig ] && [ -f $out/usr/bin/ldconfig ]; then
            cp -f $out/usr/bin/ldconfig $out/usr/sbin/ldconfig
          fi
        '';
      }
    );

  # Flatpak: drop gtk3 from buildInputs — upstream meson.build doesn't require it.
  # Note: postInstall still wraps gtk-icon-cache.trigger with gtk3; the reference
  # may persist in the closure but this is negligible (~10MB) vs what was removed.
  flatpak = finalPrev.flatpak.overrideAttrs (old: {
    buildInputs = builtins.filter (pkg: (pkg.pname or "") != "gtk3") (old.buildInputs or [ ]);
  });

  # vapoursynth-bestsource builds its own ffmpeg with `withLcms2 = true` inside
  # the upstream expression, so every generation carried a second
  # ffmpeg-9.0.2-lib (34.5 MiB) beside the one the rest of the closure uses
  # (gpu-screen-recorder and friends take the shared build). LittleCMS is
  # ffmpeg's ICC colour-management path; a frame-accurate *source* plugin hands
  # raw frames to VapourSynth and never runs an ffmpeg colour filter, so the
  # plugin is pointed at the shared build here.
  vapoursynth-bestsource = finalPrev.vapoursynth-bestsource.overrideAttrs (old: {
    buildInputs = builtins.map (
      p: if (p.pname or "") == "ffmpeg" then final.ffmpeg else p
    ) old.buildInputs;
  });

  # Ollama ROCm: build the ROCm stack for only the local GPU architecture
  # (gfx1201 — Navi 48 / RX 9070 XT) instead of all 10 default targets.
  # hipblaslt's Tensile codegen generates ~323k assembly kernels per arch;
  # scoping to one arch cuts the ROCm build from many hours to a fraction.
  # qwen3.8:27b needs a real newer engine (the 0.32.7-src-with-fake-version
  # hack lacks the qwen3.8 renderer) — vendored package copy at v0.32.15 with
  # the matching llama.cpp b10488 pin and its own vendorHash.
  # Scope llama.cpp's ROCm dependency closure to this host's GPU only
  # (gfx1201) — nixpkgs' base rocmPackages targets every GCN/RDNA arch, so
  # Tensile would generate kernels for all of them (hours of extra build).
  llama-cpp-rocm = finalPrev.llama-cpp-rocm.override {
    llama-cpp = finalPrev.llama-cpp.override {
      rocmPackages = finalPrev.rocmPackages.gfx1201;
    };
  };

  ollama-rocm = final.callPackage (inputs.self + "/packages/ollama-qwen38") {
    acceleration = "rocm";
    rocmPackages = finalPrev.rocmPackages.gfx1201;
  };

  # untangle 1.2.1 (debugpy dep for the nvim python host env): the upstream
  # GitHub tag was re-pushed, so the archive no longer matches the hash pinned
  # in nixpkgs 26.05 (fixed-output fetch fails with a hash mismatch every
  # time). Vendor the current official archive instead (version still 1.2.1;
  # relative-path pattern — see the vendored-tarball note in
  # overlays/vendored-sources.nix).
  python3 = finalPrev.python3.override {
    packageOverrides = _pfinal: pprev: {
      untangle = pprev.untangle.overrideAttrs (_: {
        src = paths.path "files/sources/untangle-1.2.1.tar.gz";
      });
      # distutils' own test suite fails under the nix builder with
      # "RuntimeError: can't start new thread" (concurrent-thread tests). The
      # package builds fine; disable check so builds are deterministic. Needed
      # on this python3 instance too (the audio stack's scons/ffado/pipewire
      # env uses it).
      distutils = pprev.distutils.overrideAttrs (_o: {
        doCheck = false;
        checkPhase = "echo 'distutils tests disabled (can\\'t start new thread)'";
      });
    };
  };

}
