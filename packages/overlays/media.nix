inputs: _final: prev: let
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
in {
  neg = {
    # Media-related tools
    beatprints = callPkg (packagesRoot + "/beatprints") {};
    webcamize = callPkg (packagesRoot + "/webcamize") {};
    rtcqs = callPkg (packagesRoot + "/rtcqs") {python3Packages = python313;};
    playscii = callPkg (packagesRoot + "/playscii") {python3Packages = python313;};
    mkvcleaner = callPkg (packagesRoot + "/mkvcleaner") {};
    rmpc = callPkg (packagesRoot + "/rmpc") {};
    cantata = callPkg (packagesRoot + "/cantata") {inherit (prev) qt6Packages;};

    # Ensure mpv is built with VapourSynth support
    mpv-unwrapped = prev.mpv-unwrapped.overrideAttrs (old: {
      buildInputs = (old.buildInputs or []) ++ [prev.vapoursynth];
      mesonFlags = (old.mesonFlags or []) ++ ["-Dvapoursynth=enabled"];
    });
  };
  pythonPackagesExtensions =
    (prev.pythonPackagesExtensions or [])
    ++ [
      (_python-final: python-prev: {
        imageio = python-prev.imageio.overridePythonAttrs (_old: {
          doCheck = false;
        });
        FreeSimpleGUI = import (packagesRoot + "/freesimplegui") {
          inherit (prev) lib fetchPypi;
          inherit (python-prev) buildPythonPackage setuptools wheel tkinter;
        };
      })
    ];
}
