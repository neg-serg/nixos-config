{ ... }:
{
  nixpkgs.overlays = [
    (_: prev: {
      multimon-ng = prev.multimon-ng.overrideAttrs (old: {
        # Raise CMake minimum version declaration to satisfy >=3.5 enforcement.
        postPatch = (old.postPatch or "") + ''
          for v in 2.8 3.0 3.1 3.2 3.3 3.4; do
            substituteInPlace CMakeLists.txt \
              --replace "cmake_minimum_required(VERSION ''${v})" "cmake_minimum_required(VERSION 3.5)"
          done
        '';
      });
    })
  ];
}
