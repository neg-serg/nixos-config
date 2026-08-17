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

  # WARNING: disableChecks MUST be last in the merge chain (//) below.
  # It calls overrideAttrs which resets any prior overrides on the same package.
  disableChecks = import ./overlays/disable-checks.nix inputs final finalPrev;
in
# Standard overlay pattern: merge top-level attributes
(functions // tools // media // dev // gui // fixTinycc // aurPorted // disableChecks)
// {
  # Carla: vendored source tarball (GitHub fetch unreliable behind the proxy)
  carla = finalPrev.carla.overrideAttrs (_: {
    src = ./../files/sources/carla-2.5.10.tar.gz;
  });

  # dpkg: nixpkgs fetches the source from git.launchpad.net (unreachable from
  # this region); vendor the official Debian release tarball (has .dist-version,
  # which get-version needs) instead. dpkg is needed by ocenaudio and
  # cloudflare-warp to unpack .debs.
  dpkg = finalPrev.dpkg.overrideAttrs (_: {
    src = ./../files/sources/dpkg-1.23.7.tar.xz;
  });

  # pffft: nixpkgs fetches the source from bitbucket.org, which is RKN-blocked
  # here (DNS-poisoned, sandboxed fetches hang); vendor the release tarball.
  # Needed by vcv-rack.
  pffft = finalPrev.pffft.overrideAttrs (_: {
    src = ./../files/sources/pffft-74d7261.tar.gz;
  });

  # fuzzysearchdatabase: same bitbucket problem — also a vcv-rack dependency.
  fuzzysearchdatabase = finalPrev.fuzzysearchdatabase.overrideAttrs (_: {
    src = ./../files/sources/fuzzysearchdatabase-23122d1.tar.gz;
  });

  # GHCi with TidalCycles library preloaded — used by tidal.nvim
  tidal-ghci = final.writeShellScriptBin "tidal-ghci" ''
    exec ${final.ghc.withPackages (ps: [ ps.tidal ])}/bin/ghci "$@" # TidalCycles GHCi wrapper
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
      dirt-samples = final.callPackage ./dirt-samples { }; # audio sample library for SuperDirt
      vowel = final.callPackage ./vowel { }; # Vowel SC quark (formant tables) used by SuperDirt
      dsh = final.callPackage ./dsh { }; # DeepSeek Harness agent CLI (dsh)
      zest = final.callPackage ./zest { }; # CLI for ZestBay plugin management (LV2 add/rm/list)
    };

  # tmd-top: real-time per-IP network traffic monitor (TUI) — pinned textual 1.0.0
  # stack on python312, see packages/tmd-top/default.nix
  tmd-top = final.callPackage ./tmd-top { };

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

  # Fix keyutils patch download failing (upstream lore.kernel.org 403)
  keyutils = finalPrev.keyutils.overrideAttrs (old: {
    patches =
      (old.patches or [ ])
      |> builtins.map (
        p:
        if builtins.isAttrs p && (p.name or "") == "raw" then
          ./../files/patches/keyutils-fix-format-specifier.patch
        else
          p
      );
  });

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
  ollama-rocm = finalPrev.ollama-rocm.override {
    rocmPackages = finalPrev.rocmPackages.gfx1201;
  };

}
