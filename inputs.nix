let
  # Use Lix Systems' flake-compat which supports lazy-tree switches
  # Pin to a specific commit for reproducibility.
  flakeCompat = import (
    builtins.fetchGit {
      url = "https://git.lix.systems/lix-project/flake-compat";
      rev = "549f2762aebeff29a2e5ece7a7dc0f955281a1d1"; # refs/heads/main at time of pin
    }
  );
  flake = flakeCompat {
    # Enable "lazy trees" for faster evaluation on large repos
    src = ./.;
    copySourceTreeToStore = false;
    useBuiltinsFetchTree = true;
  };
in
# Workaround for nilla-nix/nilla#14: mark every input with a synthetic type
builtins.mapAttrs (_: input: input // { type = "derivation"; }) flake.inputs
