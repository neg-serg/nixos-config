inputs: final: finalPrev:
let
  importOv = path: import path inputs final finalPrev;
  functions = importOv ./overlays/functions.nix;
  tools = importOv ./overlays/tools.nix;
  media = importOv ./overlays/media.nix;
  gui = importOv ./overlays/gui.nix;
  dev = importOv ./overlays/dev.nix;
  fixTinycc = importOv ./overlays/fix-tinycc.nix;
  aurPorted = import ./overlays/aur-ported.nix final finalPrev;
  vendored = importOv ./overlays/vendored-sources.nix;

  # WARNING: disableChecks MUST be last in the merge chain (//) below.
  # It calls overrideAttrs which resets any prior overrides on the same package.
  disableChecks = import ./overlays/disable-checks.nix inputs final finalPrev;
in
# Standard overlay pattern: merge top-level attributes
(functions // tools // media // dev // gui // fixTinycc // aurPorted // vendored // disableChecks)
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

  # GHCi with the TidalCycles library preloaded — used by the nvim tidal
  # ftplugin (tidal-edit / tidalctl demo/code) to boot a tidal> REPL.
  tidal-ghci = final.writeShellScriptBin "tidal-ghci" ''
    exec ${final.ghc.withPackages (ps: [ ps.tidal ])}/bin/ghci "$@"
  '';

  # Merge all pkgs.neg sub-attributes from individual overlays
  neg =
    (functions.neg or { })
    // (tools.neg or { })
    // (media.neg or { })
    // (dev.neg or { })
    // (gui.neg or { })
    // {
      game = final.callPackage ./game { };
      joern = final.callPackage ./joern { }; # Open-source code analysis platform
      superdirt = final.callPackage ./superdirt { }; # SuperDirt SC quark for TidalCycles audio engine
      superdirt-mixer = final.callPackage ./superdirt-mixer { }; # graphical mixer UI quark for SuperDirt orbits (gain/pan/reverb/EQ/compressor)
      equi = final.callPackage ./equi { }; # EQui SC quark (parametric EQ) — SuperDirtMixer dependency
      jsonlib = final.callPackage ./jsonlib { }; # JSONlib SC quark (JSON en/decoder) — SuperDirtMixer dependency
      dwg-reverb = final.callPackage ./dwg-reverb { }; # compiled SC UGen plugin: virtual room reverb (early reflections + FDN late reverb)
      dirt-samples = final.callPackage ./dirt-samples { }; # audio sample library for SuperDirt
      vowel = final.callPackage ./vowel { }; # Vowel SC quark (formant tables) used by SuperDirt
      dsh = final.callPackage ./dsh { }; # DeepSeek Harness agent CLI (dsh)
      renoise-redux = final.callPackage ./renoise-redux {
        renoiseSrc = inputs.renoise-src;
      }; # Renoise Redux VST3 plugin (licensed build)
      protoplug = final.callPackage ./protoplug { }; # Lua live-coding VST2 plugins (Fx + Gen, MIT)
      midi-transcribe = final.callPackage ./midi-transcribe { }; # audio->MIDI transcription via Sony hFT-Transformer (CPU)
      # musescore from the un-overlaid nixpkgs input: global overlays (cmake/stdenv)
      # change the derivation hash, which would force a full source build; the
      # plain build is already in the store.
      midi2sheet = final.callPackage ./midi2sheet {
        musescore = inputs.nixpkgs.legacyPackages.${final.stdenv.hostPlatform.system}.musescore;
      }; # MIDI -> sheet music PDF via headless MuseScore (piano grand staff)
      virtual-midi = final.callPackage ./virtual-midi { }; # user-space virtual ALSA seq MIDI ports (synth slots)
      wineapps = final.callPackage ./wineapps { }; # declarative Wine app manager (list/install/uninstall/run)
      renoise-osc = final.callPackage ./renoise-osc { }; # OSC client for Renoise (remote Lua eval, device/transport control)
    };

  jack-keyboard = final.callPackage ./jack-keyboard { }; # virtual MIDI keyboard for JACK/PipeWire synth hosts

  # tmd-top: real-time per-IP network traffic monitor (TUI) — pinned textual 1.0.0
  # stack on python312, see packages/tmd-top/default.nix
  tmd-top = final.callPackage ./tmd-top { };

  # tewi: TUI client for Transmission/qBittorrent/Deluge daemons
  # (python app, deps from nixpkgs + local geoip2fast, see packages/tewi/default.nix)
  tewi = final.callPackage ./tewi { };

  # Code200x Unicode font family by James Kass — Code2000 (BMP), Code2001
  # (Plane 1 ancient scripts), Code2002 (Plane 2 rare CJK), Code20X3 (Plane 3 CJK Ext G/H)
  ttf-code2000 = final.callPackage ./ttf-code2000 { };
  ttf-code2001 = final.callPackage ./ttf-code2001 { };
  ttf-code2002 = final.callPackage ./ttf-code2002 { };
  ttf-code20x3 = final.callPackage ./ttf-code20x3 { };

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
        src = ./../files/sources/untangle-1.2.1.tar.gz;
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
