# nix-det-coalesce: Determinate Nix 3.23.3 with PGO plus one native change to
# its own async path writer.
#
# Measured problem (packages/nix-det-measure, /tmp/bymotif): the writer thread
# takes whatever is queued the moment it is woken, and the evaluator produces
# derivations *slower* than one flush takes, so `writePaths()` runs 27 759
# times for 29 381 paths -- a batch of one. Every flush is two daemon round
# trips (`AddTempRoots`, then `QueryPathInfos`), 1.45 s of a 9.3 s toplevel
# evaluation on a warm store.
#
# Two changes, both inside Determinate's own writer:
#   1. let the writer wait up to 2 ms (or 4096 queued paths) for more work
#      before flushing. Nothing waits on a queued path except `waitForPath()`
#      / `waitForAllPaths()`, which now wake the thread immediately, so the
#      delay costs no evaluation time; it only decides when the write happens.
#   2. ask for the *set of valid paths* (`queryValidPaths`) instead of the full
#      `ValidPathInfo` of each one (`queryPathInfos`), whose nar hash,
#      references, deriver and signatures the caller discards.
# Measured with the counter build (packages/nix-det-measure, non-PGO, same
# eval): 27 759 batches of one path each -> 376 batches, and the writer's total
# time on the wire 1.45 s -> 0.35 s (AddTempRoots 348 ms -> 56 ms,
# QueryPathInfos 1.10 s -> 289 ms) out of a 9.3 s evaluation.
{
  lib,
  pkgs,
  inputs,
}:
import ../nix-det-allpatches {
  inherit lib pkgs inputs;
  pgo = true;
  patches = [
    ../nix-det-pgo/patches/0001-libstore-unparse-structured-attrs-without-copying-th.patch
    ../nix-det-pgo/patches/0003-libexpr-reuse-the-memoized-derivation-hash-for-a-rep.patch
    ../nix-det-pgo/patches/0004-libutil-check-the-allow-list-predecessor-before-walk.patch
    ../nix-det-pgo/patches/0005-libexpr-use-constant-error-contexts-in-builtins.any-.patch
    ./0001-libstore-coalesce-async-path-writer-flushes.patch
  ];
}
