# Patch opencode node_modules hash — neg-pkgs has a stale hash.
# Applied LAST in the overlay chain so it always wins.
inputs: _final: prev: {
  opencode = prev.opencode.overrideAttrs (old: {
    node_modules = old.node_modules.overrideAttrs (_: {
      outputHash = "sha256-1NUtprMH8GnSUqQ+mHQSC+JLU7lwzHe6XXYHe129WmE=";
      outputHashAlgo = "sha256";
      outputHashMode = "recursive";
    });
  });
}
