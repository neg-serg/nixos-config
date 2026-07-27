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
  disableChecks = import ./overlays/disable-checks.nix inputs final finalPrev;
in
# Standard overlay pattern: merge top-level attributes
(functions // tools // media // dev // gui // fixTinycc // aurPorted // disableChecks)
// {
  # Vicinae: enable browser native host for tab search integration
  vicinae = finalPrev.vicinae.overrideAttrs (old: {
    cmakeFlags =
      builtins.filter (f: f != "-DINSTALL_BROWSER_NATIVE_HOST:STRING=OFF") (old.cmakeFlags or [ ])
      ++ [ "-DINSTALL_BROWSER_NATIVE_HOST:STRING=ON" ];
  });

  # Carla: use local source (GitHub blocked by proxy)
  carla = finalPrev.carla.overrideAttrs (old: {
    src = builtins.fetchurl {
      url = "file:///tmp/carla.tar.gz";
      sha256 = "sha256-rig1sSCB9ycaawsl00uH02sCLEA3ACjKShD5D87fpmE=";
    };
  });
  # Agent multiplexer for AI coding agents (herdr)
  herdr = inputs.herdr.packages.${final.stdenv.hostPlatform.system}.default;

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
      wyoming-openai = final.callPackage ./wyoming-openai { };
      game = final.callPackage ./game { };
      superdirt = final.callPackage ./superdirt { }; # SuperDirt SC quark for TidalCycles audio engine
      dirt-samples = final.callPackage ./dirt-samples { }; # audio sample library for SuperDirt
    };

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

}
