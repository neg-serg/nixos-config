inputs: final: prev:
let
  importOv = path: import path inputs final prev;
  functions = importOv ./overlays/functions.nix;
  tools = importOv ./overlays/tools.nix;
  media = importOv ./overlays/media.nix;
  gui = importOv ./overlays/gui.nix;
  dev = importOv ./overlays/dev.nix;
in
# Merge all top-level overrides from overlays (functions/tools/media/dev), and also
# provide a combined pkgs.neg namespace aggregating their custom packages and helpers.
(functions // tools // media // dev // gui)
// {
  neg =
    (functions.neg or { })
    // (tools.neg or { })
    // (media.neg or { })
    // (dev.neg or { })
    // (gui.neg or { })
    // {
      rofi-config = final.callPackage ./rofi-config { };
      opencode = final.callPackage "${inputs.nixpkgs}/pkgs/by-name/op/opencode/package.nix" { };
      raysession = prev.raysession.overrideAttrs (old: {
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

  ncps = inputs.ncps.packages.${prev.stdenv.hostPlatform.system}.default;

  # Python with LTO optimizations
  python3-lto = prev.python3.override {
    packageOverrides = _pythonSelf: _pythonSuper: {
      enableOptimizations = true;
      enableLTO = true;
      reproducibleBuild = false;
    };
  };

  # Zen 5 Optimized Packages
  gamescope = final.neg.functions.mkZen5LtoPackage prev.gamescope;
  mangohud = final.neg.functions.mkZen5LtoPackage prev.mangohud;
  
  # Zen 5 Optimized Editor
  neovim-optimized = (final.neg.functions.mkZen5LtoPackage prev.neovim-unwrapped).overrideAttrs (old: {
    cmakeFlags = (old.cmakeFlags or [ ]) ++ [ "-DCMAKE_INTERPROCEDURAL_OPTIMIZATION=TRUE" ];
    env = (old.env or { }) // {
      NIX_CFLAGS_COMPILE = (old.env.NIX_CFLAGS_COMPILE or "") + " -flto=thin";
      NIX_LDFLAGS = (old.env.NIX_LDFLAGS or "") + " -flto=thin";
    };
  });
}

