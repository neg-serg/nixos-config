{ inputs, paths }: _final: prev:
let
  # mkMeta: shared `meta` builder for local packages — see packages/lib/mkMeta.nix.
  mkMeta = prev.callPackage ../lib/mkMeta.nix { };
in
{
  # Reach every package as `lib.mkMeta`: callPackage hands pkgs.lib to the
  # packages that declare a `lib` argument, so one additive lib extension here
  # beats adding a `mkMeta` formal to each of the ~60 package files using it.
  lib = prev.lib.extend (_libFinal: _libPrev: { inherit mkMeta; });

  # Shared helper functions under pkgs.neg.functions to DRY up overlay patterns.
  # neg sub-attributes are merged once in packages/overlay.nix — no
  # `(prev.neg or {})` accumulation here (prev is the unmodified base).
  neg = {
    functions = {
      # callPkg: callPackage with automatic `inputs` injection for packages
      # that declare an `inputs` argument (sniffed via functionArgs). Single
      # source of truth — tools.nix / gui.nix alias it instead of redefining.
      callPkg =
        path: extraArgs:
        let
          f = import path;
          formals = builtins.functionArgs f;
          # Same sniffing as `inputs`: a package declares what it wants, the
          # helper fills it in, so no call site grows a path argument by hand.
          autoArgs =
            (if builtins.hasAttr "inputs" formals then { inherit inputs; } else { })
            // (if builtins.hasAttr "paths" formals then { inherit paths; } else { });
        in
        prev.callPackage path (autoArgs // extraArgs);

      # The repo-root resolver itself, for overlays/packages that want it
      # without declaring a formal (pkgs.neg.functions.paths).
      inherit paths;

      # mkScQuark: shared builder for the pure-sclang SuperCollider quark
      # packages (no build step) — see packages/lib/mkScQuark.nix.
      mkScQuark = prev.callPackage ../lib/mkScQuark.nix { };

      inherit mkMeta;
    };
  };
}
