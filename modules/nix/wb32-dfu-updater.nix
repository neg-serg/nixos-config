_: {
  nixpkgs.overlays = [
    (_: prev: {
      wb32-dfu-updater = prev.wb32-dfu-updater.overrideAttrs (old: {
        # Raise minimum CMake requirement when upstream still declares 3.0.
        postPatch =
          (old.postPatch or "")
          + ''
            substituteInPlace CMakeLists.txt --replace "cmake_minimum_required(VERSION 3.0)" "cmake_minimum_required(VERSION 3.5)"
          '';
      });
    })
  ];
}
