# Content-addressed derivations: identical outputs skip rebuild when
# input derivation changes (version bumps, build-system tweaks).
_: _: prev: {
  vivaldi = prev.vivaldi.overrideAttrs (_: { __contentAddressed = true; });
}
