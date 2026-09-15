inputs: _final: prev: {
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
          wantsInputs = builtins.hasAttr "inputs" (builtins.functionArgs f);
          autoArgs = if wantsInputs then { inherit inputs; } else { };
        in
        prev.callPackage path (autoArgs // extraArgs);

    };
  };
}
