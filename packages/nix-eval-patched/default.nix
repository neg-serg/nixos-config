{ nixVersions }:

# nix-eval-patched: nixpkgs' Nix 2.35 rebuilt with the evaluation-speedup patch
# stack from ~/src/nix-optimized, so the flake's own eval can be measured
# against a binary that is a drop-in replacement for the system Nix.
#
# Why these patches: `nix eval` on this repo is dominated by repeated
# IsValidPath / derivation-hash / toFile bookkeeping on the daemon (see
# docs on the profiling run: 2232 derivations, ~47 % in mkDerivation).
# Interleaved A/B on the toplevel drvPath eval measured -14 % median wall time
# (8.2 s vs 9.7 s) with an identical drvPath, so this is a candidate for
# `nix.package` — deliberately NOT wired into it here.
#
# Patch order is not free: the nine patches in patches/ are cut against
# 2.35.2 + upstream #16244 ("dedup addTempRoot", commit d4c237e), which adds the
# LRU cache in remote-store-connection.hh that 0002 annotates and 0008 relies
# on. Applied alone to a pristine release, 0002 and 0008 fail. #16190
# ("srctostore on fetcher cache hit", commit 30820a5) is the other prerequisite
# of that flake, but 2.35.3 — the version this repo's nixpkgs pins — already
# contains it (`patch -p1 --dry-run` reports "Reversed (or previously applied)
# patch detected"), so re-applying it would fail the build. Hence: #16244 +
# the nine = 10 patches, carrying the "+10" in the derivation version.
#
# Checks: doCheck is left on (nixpkgs' `nix_2_35` gates on the unit tests of
# every component plus the functional test suite), so the patches are proven
# not to break eval, store or fetcher behaviour at build time — the whole
# point of the exercise is a binary that evaluates *correctly* and faster.
#
# CAVEAT for a future rollout — evaluation refuses while the worktree holds a
# path that the flake references but git does not track:
#   error: Path 'packages/questyle-ctl' in the repository "/etc/nixos"
#          is not tracked by Git.
#   To make it visible to Nix, run:
#     git -C "/etc/nixos" add -N "packages/questyle-ctl"
# Measured 2026-11-02 (smoke.sh step 8, isolated git copy of this flake plus a
# minimal flake): Determinate Nix 3.23.3 refuses *identically*, even though its
# `nix config show` reports `lazy-trees = true`. This binary does not know the
# setting at all — `nix eval` prints `warning: unknown setting 'lazy-trees'`
# (also for `eval-cores`, `parallel-eval`) — so lazy-trees is not a capability
# this package trades away: neither Nix tolerates an untracked-but-referenced
# path, and `git add -N` unblocks both. Keep `git status --porcelain -uall`
# clean of referenced-but-untracked paths before switching, whatever the Nix.
#
# Rollback plan if it ever lands in `nix.package`: nothing here sets it, so
# rollback is "revert the one line that does" + `nixos-rebuild switch` (or
# `nixos-rebuild switch --rollback` for the previous generation).
#
# Build and verify:
#   nix build /etc/nixos#nix-eval-patched --out-link /tmp/nixpatch-result
#   XDG_CACHE_HOME=/tmp/nixpatch-cache packages/nix-eval-patched/smoke.sh \
#     /tmp/nixpatch-result
# smoke.sh runs the matrix this package was accepted with: --version, eval,
# store/daemon round trip, a real build, the toplevel drvPath on a clean
# `git archive HEAD` snapshot compared against the system Nix, the same
# comparison on /etc/nixos as it is, the untracked-path refusal, and
# `git add -N` unblocking it.
let
  # Upstream #16244 — prerequisite for 0002 and 0008, vendored instead of
  # fetchpatch'd so the build needs no network and no hash upkeep; the copy is
  # byte-identical to the commit's .patch (hash in the fetchpatch this was
  # taken from: sha256-Ef1Aj3Wrm8JttWfPzRpGjeC6t/uue5oX0rAiSCjlCZk=).
  upstream = [ ./patches/upstream-16244-dedup-addtemproot.patch ];

  # The nine evaluation speedups, in the order they were cut (0001…0009).
  speedups = [
    ./patches/0001-libstore-unparse-structured-attrs-without-copying-th.patch
    ./patches/0002-libstore-skip-IsValidPath-for-paths-pinned-and-valid.patch
    ./patches/0003-libexpr-reuse-the-memoized-derivation-hash-for-a-rep.patch
    ./patches/0004-libutil-check-the-allow-list-predecessor-before-walk.patch
    ./patches/0005-libexpr-use-constant-error-contexts-in-builtins.any-.patch
    ./patches/0006-libexpr-memoize-derivationStrict-by-the-masked-deriv.patch
    ./patches/0007-libexpr-skip-re-adding-builtins.toFile-paths-written.patch
    ./patches/0008-libstore-pipeline-AddTempRoot-and-IsValidPath-in-wri.patch
    ./patches/0009-libfetchers-refresh-the-cached-git-HEAD-after-readin.patch
  ];
in
(nixVersions.nix_2_35.appendPatches (upstream ++ speedups)).overrideAttrs (prev: {
  # Spelled out rather than inherited: the repo overlay disables checks for
  # `nix` and `nixVersions.stable`, and this candidate keeps them on purpose.
  doCheck = true;

  # Keep nixpkgs' own meta (homepage, platforms, teams) — it *is* that package,
  # only patched — but drop the upstream maintainer list: nothing here is
  # upstream, per packages/AGENTS.md.
  meta = prev.meta // {
    description = "${prev.meta.description} (with evaluation-speedup patches)";
    maintainers = [ ];
  };
})
