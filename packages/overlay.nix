inputs: final: prev: let
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
    neg = (functions.neg or {}) // (tools.neg or {}) // (media.neg or {}) // (dev.neg or {});
    subsonic-tui = final.callPackage ./subsonic-tui {};
    wl-ocr = final.callPackage ./wl-ocr {};
    vermilion = final.callPackage "${inputs.vermilion}/nix/package.nix" {
      self = inputs.vermilion;
      pnpm_10 =
        final.pnpm_10
        // {
          fetchDeps = args: final.pnpm_10.fetchDeps (args // {fetcherVersion = 2;});
        };
    };
  }
