inputs: final: prev: let
  packagesRoot = inputs.self + "/packages";
  callPkg = path: extraArgs: let
    f = import path;
    wantsInputs = builtins.hasAttr "inputs" (builtins.functionArgs f);
    autoArgs =
      if wantsInputs
      then {inherit inputs;}
      else {};
  in
    prev.callPackage path (autoArgs // extraArgs);
  python313 = prev.python313Packages;
  laion_clap_pkg = callPkg (packagesRoot + "/laion-clap") {
    python3Packages = python313;
    inherit (prev) fetchurl;
  };
in {
  neg = let
    blissify_rs = callPkg (packagesRoot + "/blissify-rs") {};
  in {
    inherit blissify_rs;
    # Media-related tools
    mkvcleaner = callPkg (packagesRoot + "/mkvcleaner") {};
    rmpc = callPkg (packagesRoot + "/rmpc") {};
    cantata = callPkg (packagesRoot + "/cantata") {inherit (prev) qt6Packages;};
    "blissify-rs" = blissify_rs;
    "laion-clap" = laion_clap_pkg;
    laion_clap = laion_clap_pkg;
    # music_clap depends on laion_clap, which already propagates the
    # heavy Python deps (torch/torchaudio/torchvision, numpy, etc.).
    # Passing them explicitly here causes callPackage to complain about
    # unexpected arguments because the package does not declare them.
    # Keep the call minimal.
    music_clap = callPkg (packagesRoot + "/music-clap") {
      python3Packages = python313;
      laion_clap = laion_clap_pkg;
    };

    # Yabridgemgr helpers (plumbing + plugins)
    yabridgemgr = rec {
      build_prefix = callPkg (packagesRoot + "/yabridgemgr/plumbing/build_prefix.nix") {};
      mount_prefix = callPkg (packagesRoot + "/yabridgemgr/plumbing/mount_prefix.nix") {wineprefix = build_prefix;};
      umount_prefix = callPkg (packagesRoot + "/yabridgemgr/plumbing/umount_prefix.nix") {};
      plugins = rec {
        voxengo_span = callPkg (packagesRoot + "/yabridgemgr/plugins/voxengo_span.nix") {};
        "voxengo-span" = voxengo_span;
        piz_midichordanalyzer = callPkg (packagesRoot + "/yabridgemgr/plugins/piz_midichordanalyzer.nix") {};
        valhalla_supermassive = callPkg (packagesRoot + "/yabridgemgr/plugins/valhalla_supermassive.nix") {};
      };
    };

    # Ensure mpv is built with VapourSynth support
    mpv-unwrapped = prev.mpv-unwrapped.overrideAttrs (old: {
      buildInputs = (old.buildInputs or []) ++ [prev.vapoursynth];
      mesonFlags = (old.mesonFlags or []) ++ ["-Dvapoursynth=enabled"];
    });
  };
}
