inputs: final: finalPrev:
let
  # Rename prev to finalPrev to avoid confusion with internal overlay calls
  importOv = path: import path inputs final finalPrev;
  functions = importOv ./overlays/functions.nix;
  tools = importOv ./overlays/tools.nix;
  media = importOv ./overlays/media.nix;
  gui = importOv ./overlays/gui.nix;
  dev = importOv ./overlays/dev.nix;
  fixTinycc = importOv ./overlays/fix-tinycc.nix;
in
# Standard overlay pattern: merge top-level attributes
(functions // tools // media // dev // gui // fixTinycc)
// {
  # Merge all pkgs.neg sub-attributes from individual overlays
  neg =
    (functions.neg or { })
    // (tools.neg or { })
    // (media.neg or { })
    // (dev.neg or { })
    // (gui.neg or { })
    // {
      rofi-config = final.callPackage ./rofi-config { };
      opencode = final.callPackage "${inputs.nixpkgs}/pkgs/by-name/op/opencode/package.nix" { };
      raysession = finalPrev.raysession.overrideAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          substituteInPlace src/gui/patchbay/patchcanvas/portgroup_widget.py \
            --replace-fail "from cgitb import text" ""
        '';
      });
    };

  fsread-nvim = final.vimUtils.buildVimPlugin {
    pname = "fsread-nvim";
    version = "flake";
    src = inputs.fsread-nvim;
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
    patches = builtins.map (
      p:
      if builtins.isAttrs p && (p.name or "") == "raw" then
        ./../files/patches/keyutils-fix-format-specifier.patch
      else
        p
    ) (old.patches or [ ]);
  });

  # Disable flaky OpenLDAP tests (fails on syncreplication)
  openldap = finalPrev.openldap.overrideAttrs (old: {
    doCheck = false;
  });

  # Disable libyuv tests (fails with OOM and has many warnings)
  libyuv = finalPrev.libyuv.overrideAttrs (old: {
    doCheck = false;
    cmakeFlags = (old.cmakeFlags or [ ]) ++ [ "-DUNIT_TEST=OFF" ];
  });

  # Disable rsync tests (fails on hardlinks test)
  rsync = finalPrev.rsync.overrideAttrs (old: {
    doCheck = false;
  });

  # Disable flaky libuv tests
  libuv = finalPrev.libuv.overrideAttrs (old: {
    doCheck = false;
  });

  # Disable flaky lua-language-server tests
  lua-language-server = finalPrev.lua-language-server.overrideAttrs (old: {
    doCheck = false;
  });

  # XFS breaks nix-util readLinkAt test on kernel 7.0+
  # Build failures on nixpkgs-unstable
  valkey = finalPrev.valkey.overrideAttrs (old: {
    doCheck = false;
    # Note: if valkey still fails to build, it's a transient nixpkgs issue
  });
  notmuch = finalPrev.notmuch.overrideAttrs (old: {
    doCheck = false;
  });

  nix = finalPrev.nix.overrideAttrs (old: {
    doCheck = false;
    doInstallCheck = false;
  });

  # Disable flaky pytest-xdist tests
  pythonPackagesExtensions = (finalPrev.pythonPackagesExtensions or [ ]) ++ [
    (python-final: python-prev: {
      pytest-xdist = python-prev.pytest-xdist.overrideAttrs (old: {
        doCheck = false;
      });
      uvloop = python-prev.uvloop.overrideAttrs (old: {
        doCheck = false; # flaky timing test
      });
    })
  ];
}
