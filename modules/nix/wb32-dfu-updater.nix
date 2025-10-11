{ ... }:
{
  nixpkgs.overlays = [
    (_: prev: {
      wb32-dfu-updater = prev.wb32-dfu-updater.overrideAttrs (old: {
        # Raise minimum CMake requirement to satisfy >=3.5 policy enforced by recent CMake.
        patches = (old.patches or []) ++ [
          ./patches/wb32-dfu-updater-min-cmake-3_5.patch
        ];
      });
    })
  ];
}
