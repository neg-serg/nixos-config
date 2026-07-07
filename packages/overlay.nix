inputs: final: finalPrev:
let
  # Rename prev to finalPrev to avoid confusion with internal overlay calls
  importOv = path: import path inputs final finalPrev;
  functions = importOv ./overlays/functions.nix;
  tools = importOv ./overlays/tools.nix;
  media = importOv ./overlays/media.nix;
  gui = importOv ./overlays/gui.nix;
  dev = importOv ./overlays/dev.nix;
  fonts = importOv ./overlays/fonts.nix;
  fixTinycc = importOv ./overlays/fix-tinycc.nix;
  aurPorted = import ./overlays/aur-ported.nix final finalPrev;
  disableChecks = import ./overlays/disable-checks.nix inputs final finalPrev;
  ca = importOv ./overlays/ca.nix;
in
# Standard overlay pattern: merge top-level attributes
(functions // tools // media // dev // gui // fonts // fixTinycc // aurPorted // disableChecks // ca)
// {
  # Override opencode to build from flake input source (latest git)
  opencode =
    (final.callPackage "${inputs.nixpkgs}/pkgs/by-name/op/opencode/package.nix" { }).overrideAttrs
      (old: {
        src = inputs.opencode;
        version = inputs.opencode.shortRev or "dev-${inputs.opencode.lastModifiedDate}";
        node_modules = old.node_modules.overrideAttrs (nmOld: {
          outputHash = "sha256-9oSXcvvISB6WAqI6f/GBZ3i9IBwYrRQvKs82SLibJNo=";
          outputHashAlgo = "sha256";
          outputHashMode = "recursive";
        });
      });

  # Agent multiplexer for AI coding agents (herdr)
  herdr = inputs.herdr.packages.${final.stdenv.hostPlatform.system}.default;

  # Merge all pkgs.neg sub-attributes from individual overlays
  neg =
    (functions.neg or { })
    // (tools.neg or { })
    // (media.neg or { })
    // (dev.neg or { })
    // (gui.neg or { })
    // {
      bazecor = final.callPackage ./bazecor-appimage { };

      opencode-dev =
        (final.callPackage "${inputs.nixpkgs}/pkgs/by-name/op/opencode/package.nix" { }).overrideAttrs
          (old: {
            src = inputs.opencode;
            version = inputs.opencode.shortRev or "dev-${inputs.opencode.lastModifiedDate}";
          });
      raysession = finalPrev.raysession.overrideAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          substituteInPlace src/gui/patchbay/patchcanvas/portgroup_widget.py \
            --replace-fail "from cgitb import text" ""
        '';
      });
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

}
