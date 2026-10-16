# Upstream series for `psyclyx/fix` — prepared, not sent

Everything needed to hand our changes to the upstream evaluator, plus the story of how it was
prepared. **No pull request and no issue has been opened against `psyclyx/fix`** (checked: zero
issues/PRs by `neg-serg` there). The series lives in the fork and in this directory; see "Sending
it" at the end.

## Context: why `fix` left this repository

`fix` was packaged here (patched master + vendored zig dependencies, feature flag
`features.cli.fix`) and removed again in commmits `66ea322d0` (`[cli/fix] Drop the fix evaluator`)
and `5e1f87fe1` (`[cli/fix] Drop the fix flag, overlay and flake exports`). The reason was measured,
not assumed — `scripts/dev/rollout-bench.sh` (`just bench-rollout`) times one real, minimal rollout
per engine on this host:

| engine      | 5-round medians (warm store) |
| ----------- | ---------------------------- |
| `fix build` | 18.85 s                      |
| `nix build` | 18.32 s                      |

So the "fast evaluator" buys nothing on this configuration, while it cost six local patches to keep
building, a 43.9 MiB closure, no evaluation cache between invocations (Nix has one), and a
store-path divergence from Nix: for derivations whose text comes from a *built* file (`readFile` of
a derivation, e.g. nixpkgs' `replaceVars` + `readFile`) fix records fewer `inputSrcs`, so a
fix-built toplevel never matches Nix's. As a cross-check of this configuration it also found nothing
of its own — every blocker we hit was a fix defect, not a config defect.

That is why the patches below are worth offering upstream: they are fixes to the evaluator, prepared
while it was still in use here.

## The series

Base: `e0c1f6d699894e3fcbb480c8e7445ddd3b9467fa` — upstream `main`, still HEAD (`git ls-remote`).
Every patch applies cleanly to a fresh clone of that commit and is `zig fmt --check`-clean.

| patch                           | topic                                                                                                                        | upstream hook                        | verification                                                                                                                                                                                                                                                                                      |
| ------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- | ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `01-json-control-chars.patch`   | `__json` must escape control characters                                                                                      | closes issue **#61**                 | **holds** — property test over every control byte plus valid UTF-8; `.drvPath` of a probe equals Nix's, so `__json` is byte-identical                                                                                                                                                             |
| `02-pure-gated-constants.patch` | pure eval omits `builtins.currentSystem`/`currentTime`, and `setPureEval` rebuilds the cached `builtins` attrset             | issue **#53**                        | **holds** — Nix oracle matches; impure→pure→impure flip verified                                                                                                                                                                                                                                  |
| `03-catchable-pure-gates.patch` | an empty `builtins.nixPath` and a catchable not-found; `pathExists` → `false`; explicit search-path lists stay read-confined | issue **#52**                        | **broken → fixed, re-verified holds** — the first revision leaked `/etc/hostname` through `builtins.findFile [{ path = "/etc"; }]`; now the base and the resolved candidate both pass `enforceReadPath`, and every escape the verifier tried is refused                                           |
| `04-git-worktree-root.patch`    | a bare path that is a git work-tree root resolves as `git+file`                                                              | adjacent to issues **#55** / **#50** | **broken → fixed, re-verified holds** — two rounds: an unborn HEAD (`git init`) must keep the directory copy, and so must empty/garbage/missing/symlinked HEADs; only a provably resolvable HEAD takes the git route                                                                              |
| `05-read-cap-diagnostic.patch`  | name the file that exceeds the read cap                                                                                      | part of the large-file issue         | **holds** — red→green, message on stderr, cap and error unchanged                                                                                                                                                                                                                                 |
| `06-large-file-streaming.patch` | stream files above the cap through the NAR writer                                                                            | part of the large-file issue         | **holds** — byte-identical to the cached path across sizes {0…73} at cap 64, branch switch exactly at `size > cap`, same SHA-256 over a 4 MiB+123 NAR, peak 384 B vs 6.3 MB                                                                                                                       |
| `07-git-fallback.patch`         | fall back to the system `git` when the built-in client cannot fetch (git.kernel.org)                                         | new issue                            | **broken → fixed, re-verified holds** — the first revision deinited the cache repository twice on the failure path (SIGSEGV); now a missing `git`, a failing stub and repeated failures all return `FetchGitFailed`, gdb-clean, plus a green end-to-end fallback against a static HTTP repository |

`verification.md` carries the full evidence per patch, including what each verifier could **not**
check. Known, honest gaps: upstream CI's `check-static` and `check-models` could not run here (the
dependency host `git.lilithsemi.com` does not answer this machine, so local builds used vendored
path dependencies), the corner cases listed per patch, and `07`'s submodule path (the fallback is
not wired there).

## Sending it

The fork: https://github.com/neg-serg/fix — one branch per topic, each exactly one commit on top of
upstream `main`, authored as the repository owner:

```
json-control-chars   pure-gated-constants   catchable-pure-gates   git-worktree-root
read-cap-diagnostic  large-file-streaming   git-fallback           upstream-notes
```

`upstream-notes` mirrors this directory, so the texts are readable in the browser. Ready-made
"create pull request" links:

```
https://github.com/psyclyx/fix/compare/main...neg-serg:fix:<branch>?expand=1
```

Suggested order, cheapest acceptance first: the two new issue reports
(`issues/01-kernel-org-fetch.md`, `issues/02-large-file-read-cap.md`) and `01` (closes #61), then
`02` (#53) and `03` (#52), then `04`, and `06`/`07` after the maintainer answers the design
questions their PR bodies ask (a configurable cap instead of streaming; opt-in rather than opt-out
for the git fallback).

To send from a shell:

```console
$ gh repo fork psyclyx/fix --clone=false        # already done
$ git clone https://github.com/neg-serg/fix && cd fix
$ git push origin <branch>                      # add new commits, then open the PR
```

To re-verify a patch locally, clone upstream and apply the patch the way the verifiers did — note
that a *build* here needs the vendored zig dependencies, which lived in the removed `packages/fix`
(`git revert 66ea322d0` restores them).

## Files here

- `0N-*.patch` — the seven patches, exactly as pushed to the fork.
- `pr-bodies.md` — one ready-to-paste PR body per patch.
- `verification.md` — the verification journal: verdict, evidence and open gaps per patch, including
  the two rounds that found real defects.
- `issues/` — the two issue drafts (`01-kernel-org-fetch.md`, `02-large-file-read-cap.md`) with
  reproductions and evidence.
