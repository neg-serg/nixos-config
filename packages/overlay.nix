inputs: final: finalPrev:
let
  # Rename prev to finalPrev to avoid confusion with internal overlay calls
  importOv = path: import path inputs final finalPrev;
  functions = importOv ./overlays/functions.nix;
  tools = importOv ./overlays/tools.nix;
  media = importOv ./overlays/media.nix;
  gui = importOv ./overlays/gui.nix;
  dev = importOv ./overlays/dev.nix;
in
# Standard overlay pattern: merge top-level attributes
(functions // tools // media // dev // gui)
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

  ncps = inputs.ncps.packages.${finalPrev.stdenv.hostPlatform.system}.default;

  # Python with LTO optimizations
  python3-lto = finalPrev.python3.override {
    packageOverrides = _pythonSelf: _pythonSuper: {
      enableOptimizations = true;
      enableLTO = true;
      reproducibleBuild = false;
    };
  };

  # Zen 5 Optimized Packages
  gamescope = final.neg.functions.mkZen5LtoPackage finalPrev.gamescope;
  mangohud = final.neg.functions.mkZen5LtoPackage finalPrev.mangohud;

  # Zen 5 Optimized Editor
  neovim-optimized =
    (final.neg.functions.mkZen5LtoPackage finalPrev.neovim-unwrapped).overrideAttrs
      (old: {
        cmakeFlags = (old.cmakeFlags or [ ]) ++ [ "-DCMAKE_INTERPROCEDURAL_OPTIMIZATION=TRUE" ];
        env = (old.env or { }) // {
          NIX_CFLAGS_COMPILE = (old.env.NIX_CFLAGS_COMPILE or "") + " -flto=thin";
          NIX_LDFLAGS = (old.env.NIX_LDFLAGS or "") + " -flto=thin";
        };
      });

  # Google's Antigravity networking protocol
  antigravity-manual = final.callPackage ./antigravity/package.nix { };

  # Fix keyutils patch download failing (upstream lore.kernel.org 403)
  keyutils = finalPrev.keyutils.overrideAttrs (old: {
    patches = builtins.map (
      p:
      if builtins.isAttrs p && (p.name or "") == "raw" then
        inputs.self + "/files/patches/keyutils-fix-format-specifier.patch"
      else
        p
    ) (old.patches or [ ]);
  });

  # Disable flaky OpenLDAP tests (fails on syncreplication)
  openldap = finalPrev.openldap.overrideAttrs (old: {
    doCheck = false;
  });
}
