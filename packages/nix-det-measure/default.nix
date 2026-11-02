# Temporary measurement build, not for shipping: Determinate Nix 3.23.3 built
# *without* PGO plus a counter patch that logs protocol batches, derivation
# text cost and duplicate-instantiation counts to $NIX_BYMOTIF_STATS.
# Used only to decide which evaluation-speedup ideas are worth implementing;
# see /tmp/bymotif for the analysis and the raw logs.
{
  lib,
  pkgs,
  inputs,
}:
# The measurement build reuses the PGO patch stack exactly as
# packages/nix-det-pgo ships it - a copy here would drift.
# allow-relative: the sibling recipe and its patch stack are shared by design.
import ../nix-det-allpatches {
  inherit lib pkgs inputs;
  pgo = false;
  patches = [
    ../nix-det-pgo/patches/0001-libstore-unparse-structured-attrs-without-copying-th.patch # allow-relative: shared patch stack, no copy to drift
    ../nix-det-pgo/patches/0003-libexpr-reuse-the-memoized-derivation-hash-for-a-rep.patch # allow-relative: shared patch stack, no copy to drift
    ../nix-det-pgo/patches/0004-libutil-check-the-allow-list-predecessor-before-walk.patch # allow-relative: shared patch stack, no copy to drift
    ../nix-det-pgo/patches/0005-libexpr-use-constant-error-contexts-in-builtins.any-.patch # allow-relative: shared patch stack, no copy to drift
    ./measure.patch
  ];
}
