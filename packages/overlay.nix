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
  neg = (functions.neg or { }) // (tools.neg or { }) // (media.neg or { }) // (dev.neg or { });

  fsread-nvim = final.vimUtils.buildVimPlugin {
    pname = "fsread-nvim";
    version = "unstable";
    src = final.fetchFromGitHub {
      owner = "neg-serg";
      repo = "fsread.nvim";
      rev = "main";
      hash = "sha256-iwMioDga7dCori2FeBo3lYG27ji8pLnM2VZu9iJn/8w=";
    };
  };

  # Python with LTO optimizations
  python3-lto = prev.python3.override {
    packageOverrides = _pythonSelf: _pythonSuper: {
      enableOptimizations = true;
      enableLTO = true;
      reproducibleBuild = false;
    };
  };
}
