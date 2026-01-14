inputs: _final: prev:
let
  packagesRoot = inputs.self + "/packages";
  callPkg =
    path: extraArgs:
    let
      f = import path;
      wantsInputs = builtins.hasAttr "inputs" (builtins.functionArgs f);
      autoArgs = if wantsInputs then { inherit inputs; } else { };
    in
    prev.callPackage path (autoArgs // extraArgs);
  python313 = prev.python313Packages;
  laion_clap_pkg = callPkg (packagesRoot + "/laion-clap") {
    python3Packages = python313;
    inherit (prev) fetchurl;
  };
in
{
  ffmpeg = prev.ffmpeg.override {
    withSdl2 = false;
    buildFfplay = false;
  };
  ffmpeg-full = prev.ffmpeg-full.override {
    withSdl2 = false;
    buildFfplay = false;
  };

  swayimg = prev.swayimg.overrideAttrs (old: {
    env.NIX_CFLAGS_COMPILE =
      toString (old.env.NIX_CFLAGS_COMPILE or "")
      + " -O3 -ftree-parallelize-loops=8 -floop-parallelize-all";
  });
  neg =
    let
      blissify_rs = callPkg (packagesRoot + "/blissify-rs") { };
    in
    {
      inherit blissify_rs;
      # Media-related tools
      webcamize = callPkg (packagesRoot + "/webcamize") { };
      rtcqs = callPkg (packagesRoot + "/rtcqs") { python3Packages = python313; };
      playscii = callPkg (packagesRoot + "/playscii") { python3Packages = python313; };
      mkvcleaner = callPkg (packagesRoot + "/mkvcleaner") { };
      lucida = callPkg (packagesRoot + "/lucida-downloader") { };
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

      # Ensure mpv is built with VapourSynth support
      mpv-unwrapped = prev.mpv-unwrapped.overrideAttrs (old: {
        buildInputs = (old.buildInputs or [ ]) ++ [ prev.vapoursynth ];
        mesonFlags = (old.mesonFlags or [ ]) ++ [ "-Dvapoursynth=enabled" ];
      });
    };
  pythonPackagesExtensions = (prev.pythonPackagesExtensions or [ ]) ++ [
    (_python-final: python-prev: {
      imageio = python-prev.imageio.overridePythonAttrs (_old: {
        doCheck = false;
      });
      FreeSimpleGUI = import (packagesRoot + "/freesimplegui") {
        inherit (prev) lib fetchPypi;
        inherit (python-prev)
          buildPythonPackage
          setuptools
          wheel
          tkinter
          ;
      };
      pylette = python-prev.pylette.overridePythonAttrs (_old: {
        doCheck = false;
        # Force disable check phases
        checkPhase = "true";
        pytestCheckPhase = "true";
        installCheckPhase = "true";
        catchConflicts = false;
      });
    })
  ];
}
