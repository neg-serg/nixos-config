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
  vendored = importOvP ./overlays/vendored-sources.nix;

  # Rust slimming: `inputs.rust-pkgs.lib.slim` — the extracted crates' own
  # repository owns the two measured levers (lib/rust-slim.nix) and exports the
  # wrapper, so this tree keeps the size behaviour without a second copy.
  # The name lists are the single place that knows which packages are Rust —
  # `neg` names live under pkgs.neg, `top` names are the top-level attributes
  # the chunk overlays define (elio/lazytail are defined below and
  # wrapped at their definition instead).
  rustSlim = inputs.rust-pkgs.lib.slim;
  rustNegNames = [
    "aurora"
    "aurora-headphones"
    "aurora-plugins"
    "blizzard"
    "dnsglobe"
    "dsh-patch"
    "game"
    "hwctl"
    "hypr-focus"
    "hypr-rearrange"
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
    "nixbuild-status"
    "questyle-ctl"
    "renoise-osc"
    "scratchpad-geometry"
    "sing-box-proxy"
    "swayimg-actions"
    "telegram-notify"
    "tgchat-rs"
    "tidalctl"
    "tint"
    "topowall"
    "vivaldi-prefs"
    "wineapps"
    "zalgo"
  ];
  rustTopNames = [
    "craft-anything"
    "figcraft"
    "pw-audioshare"
    "pwroute"
    "solidcraft"
    "sonda"
    "tint"
    "wl"
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

  # GHCi with the TidalCycles library preloaded — used by the nvim tidal
  # ftplugin (tidal-edit / tidalctl demo/code) to boot a tidal> REPL.
  tidal-ghci = final.writeShellScriptBin "tidal-ghci" ''
    exec ${final.ghc.withPackages (ps: [ ps.tidal ])}/bin/ghci "$@"
  '';

  # Merge all pkgs.neg sub-attributes from individual overlays, then slim the
  # Rust ones (inputs.rust-pkgs.lib.slim).
  neg =
    let
      base =
        (functions.neg or { })
        // (tools.neg or { })
        // (media.neg or { })
        // (dev.neg or { })
        // (gui.neg or { })
        // {
          game = final.callPackage (inputs.rust-pkgs + "/game/package.nix") { }; # Unified game launcher
          dsh-patch = final.callPackage (inputs.rust-pkgs + "/dsh-patch/package.nix") { }; # count-asserted patcher for dsh bundles and profiles
          # The harness is the dsh-app repository's recipe
          # (github:neg-serg/dsh-app), built against this package set; the
          # patcher it runs lives in rust-pkgs and is passed in, so the
          # repository needs no second copy of it.
          dsh = final.callPackage (inputs.dsh-app + "/package.nix") { inherit (final.neg) dsh-patch; }; # DeepSeek Harness agent CLI (dsh)
          # Context budget + tool-protocol guard in front of llama-swap; owned by
          # github:neg-serg/llm-proxy, built against this package set.
          llm-proxy = final.callPackage (inputs.llm-proxy + "/package.nix") { };
          # Unattended GPU jobs (VRAM preflight, systemd runner, report), owned by
          # github:neg-serg/nightjob; the wrapper PATH is the repository's, so the
          # session's hyprctl/llmctl stay behind it.
          nightjob = final.callPackage (inputs.nightjob + "/package.nix") { }; # nightjob: overnight GPU jobs with a VRAM budget and a report
          # The player and its catalogue CLI are the aurora repository's own recipe
          # (`nix/package.nix`), built against this package set — the same
          # `callPackage` line as llm-proxy above and rust-pkgs below.
          aurora = final.callPackage (inputs.aurora + "/nix/package.nix") { }; # aurora: local MPD player with a Vulkan UI
          aurora-headphones = final.callPackage (inputs.aurora + "/nix/package.nix") {
            toolsOnly = true;
          }; # aurora-headphones: the headphone model catalogue CLI, without the player's Vulkan closure
          # The eight plugins that talk to the rest of the machine, as programs the player spawns
          # (a JSON line each way, no shared library). The derivation is the plugins repository's
          # own `nix/package.nix`, so the layout of a plugin directory is decided where the
          # programs live; this line only pins the revision it builds from.
          aurora-plugins = final.callPackage (inputs.aurora-plugins + "/nix/package.nix") { }; # aurora-plugins: autodj, lyrics, mpris, musicbrainz, notify, remaining, scrobble and spectroscope as programs
          renoise-redux = final.callPackage ./renoise-redux {
            renoiseSrc = inputs.renoise-src;
          }; # Renoise Redux VST3 plugin (licensed build)
          questyle-ctl = final.callPackage (inputs.rust-pkgs + "/questyle-ctl/package.nix") { }; # USB/ALSA/PipeWire + vendor HID channel of the Questyle QCC dongle
          pleamar-sysmon = final.callPackage ./pleamar-sysmon { }; # pleamar system monitor worker (procfs/sysfs, JSON lines)
          pleamar-weather = final.callPackage ./pleamar-weather { }; # pleamar weather worker (Open-Meteo/MET Norway/wttr.in, JSON lines)
          pleamar-kbdlayout = final.callPackage ./pleamar-kbdlayout { }; # pleamar keyboard-layout worker (hyprctl, JSON lines)
          pleamar-theme = final.callPackage ./pleamar-theme { }; # pleamar theme pipeline (wallpaper colours -> theme.plm)
          pleamar-calendar = final.callPackage ./pleamar-calendar { }; # pleamar calendar worker (khal, holidays, production calendar, JSON lines)
          pleamar-picker = final.callPackage ./pleamar-picker { }; # picker scene commands (wallpaper still/apply, deck CLI)
          pleamar-harness = final.callPackage ./pleamar-harness { }; # pleamar developer harnesses (measure, describe-snap, smoke) as Rust binaries
          local-bin-scripts = final.callPackage (inputs.rust-pkgs + "/local-bin-scripts/package.nix") { }; # Rust ports of the small local-bin helper scripts
          local-bin-desktop = final.callPackage (inputs.rust-pkgs + "/local-bin-desktop/package.nix") { }; # Rust ports of the desktop/media local-bin helpers
          local-bin-audio = final.callPackage (inputs.rust-pkgs + "/local-bin-audio/package.nix") { }; # Rust ports of the audio helpers (audio-diag, jam, sc-live, ...)
          local-bin-misc = final.callPackage (inputs.rust-pkgs + "/local-bin-misc/package.nix") { }; # Rust ports of the last local-bin helpers (pb, any, v, pw-jack wrappers)
          local-bin-zsh = final.callPackage (inputs.rust-pkgs + "/local-bin-zsh/package.nix") { }; # Rust ports of the last zsh helpers (iommu-info, music-rename, music-tui, pl, read_documents)
          local-bin-zsh-extra = final.callPackage (
            inputs.rust-pkgs + "/local-bin-zsh-extra/package.nix"
          ) { }; # Rust ports of gh-issues-export, mpd_del_album, sx, sys-relief, vol, win-vm
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
          local-bin-system = final.callPackage (inputs.rust-pkgs + "/local-bin-system/package.nix") { }; # Rust ports of the system-level local-bin/bin helpers
          wineapps = final.callPackage (inputs.rust-pkgs + "/wineapps/package.nix") { }; # declarative Wine app manager (list/install/uninstall/run)
          renoise-osc = final.callPackage (inputs.rust-pkgs + "/renoise-osc/package.nix") { }; # OSC client for Renoise (remote Lua eval, device/transport control)
          scratchpad-geometry = final.callPackage (
            inputs.rust-pkgs + "/scratchpad-geometry/package.nix"
          ) { }; # persist Hyprland scratchpad rects across show/hide
          hypr-rearrange = final.callPackage (inputs.rust-pkgs + "/hypr-rearrange/package.nix") { }; # move windows to the workspaces the config routes them to
          minibbs = final.callPackage (inputs.rust-pkgs + "/minibbs/package.nix") { }; # tiny BBS-style message board (SQLite + HTTP)
          zalgo = final.callPackage (inputs.rust-pkgs + "/zalgo/package.nix") { }; # cursed-text generator (combining marks on stdin)
          blizzard = final.callPackage (inputs.rust-pkgs + "/blizzard/package.nix") { }; # animated black-metal blizzard WebP generator (fastfetch logos)
          music-apply-tags = final.callPackage (inputs.rust-pkgs + "/music-apply-tags/package.nix") { }; # write ML mood/style into audio tags (was scripts/dev/music-apply-tags.py)
          vivaldi-prefs = final.callPackage (inputs.rust-pkgs + "/vivaldi-prefs/package.nix") { }; # re-assert managed Vivaldi preferences
          wallpaper-palettes = final.callPackage ./wallpaper-palettes { }; # matugen schemes per wallpaper (picker cards)
          local-bin-tools = final.callPackage (inputs.rust-pkgs + "/local-bin-tools/package.nix") { }; # small $PATH helpers (fetch-covers, gen-unbound-hosts, menu-search, ren, …)
          swayimg-actions = final.callPackage (inputs.rust-pkgs + "/swayimg-actions/package.nix") { }; # rotate/move/copy/wallpaper/range actions for swayimg (Rust port of the local-bin helper)
        };
    in
    base
    // builtins.listToAttrs (
      map (n: {
        name = n;
        value = rustSlim base.${n};
      }) rustNegNames
    );

  # tmd-top: real-time per-IP network traffic monitor (TUI) — pinned textual 1.0.0
  # stack on python312, see packages/tmd-top/default.nix

  # lazytail: terminal log viewer (ratatui) with live filtering, follow mode and
  # an MCP server — see packages/lazytail/default.nix
  lazytail = rustSlim (final.callPackage ./lazytail { });

  # elio: three-pane terminal file manager (places / files / preview) with inline
  # image previews, archive handling and trash — see packages/elio/default.nix
  elio = rustSlim (final.callPackage ./elio { });

  # tewi: TUI client for Transmission/qBittorrent/Deluge daemons
  # (python app, deps from nixpkgs + local geoip2fast, see packages/tewi/default.nix)

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

  # xdg-desktop-portal takes the `flatpak` package only for the Flatpak portal
  # interface XML (fed to gdbus-codegen) and for the PATH wrapGApps adds; no
  # code links libflatpak. Dropping both keeps the Flatpak manager out of the
  # system closure — nothing here runs Flatpak apps, and the portal tests
  # synthesize their own fake `flatpak` executable.
  xdg-desktop-portal = finalPrev.xdg-desktop-portal.overrideAttrs (old: {
    mesonFlags = (old.mesonFlags or [ ]) ++ [ "-Dflatpak-interfaces=disabled" ];
    buildInputs = builtins.filter (pkg: (pkg.pname or "") != "flatpak") (old.buildInputs or [ ]);
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

  # Ollama: the ROCm build is nixpkgs' own `ollama-rocm` again (0.40.16 at the
  # 2026-11-21 pin, substitutable from cache.nixos.org). The local copy under
  # packages/ollama-qwen38 existed because 0.32.x lacked the qwen3.8 renderer
  # and its per-arch ROCm build was not cached; both reasons are gone.

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
