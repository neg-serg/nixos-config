{ ... }:
{
  nixpkgs.overlays = [
    (_: prev: {
      imhex = prev.imhex.overrideAttrs (old:
        let
          appendFlag = flags:
            if flags == "" then
              "-Wno-error=deprecated-declarations"
            else
              flags + " -Wno-error=deprecated-declarations";
          oldEnv = old.env or {};
          flagUpdate =
            if oldEnv ? NIX_CFLAGS_COMPILE then {
              env = oldEnv // {
                NIX_CFLAGS_COMPILE = appendFlag (oldEnv.NIX_CFLAGS_COMPILE or "");
              };
            } else if old ? NIX_CFLAGS_COMPILE then {
              NIX_CFLAGS_COMPILE = appendFlag (old.NIX_CFLAGS_COMPILE or "");
            } else {
              NIX_CFLAGS_COMPILE = "-Wno-error=deprecated-declarations";
            };
        in
        {
          # Raise embedded edlib's CMake minimum version to satisfy >=3.5 policy.
          patches = (old.patches or []) ++ [
            ./patches/imhex-edlib-min-cmake-3_5.patch
          ];
        }
        // flagUpdate);
    })
  ];
}
