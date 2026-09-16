# Build Performance Analysis

## Current Bottlenecks

| Factor                                                           | Impact                                                                                              | What to do                                                                     |
| ---------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| **`builtins.pathExists` with absolute paths**                    | Slow evaluation (impure), breaks eval cache                                                         | Replaced by a feature flag in `session/chat.nix`                               |
| **Full profile (`profile = "full"`)**                            | All features enabled → more builds                                                                  | Use `features.devSpeed.enable` for fast iteration                              |
| **`cores = 2`**                                                  | Each build gets 2 cores; with 32/16 threads more is possible                                        | Raise to `cores = 4` (fewer parallel jobs = each finishes faster)              |
| **`max-jobs = 16`**                                              | Many parallel builds eat memory                                                                     | Lower to `max-jobs = 8` for a desktop with 32 GB RAM — fewer OOMs              |
| **No remote builder**                                            | Everything builds locally; the CPU idles under load                                                 | Configure `builders` on a separate machine or VPS                              |
| **CA derivations (`ca-derivations`)**                            | Content-addressed — rebuilding after a dependency change does not touch downstream (not yet stable) | Keep enabled — it already pays off                                             |
| **`builtins.readFile` in modules/media/audio/core-packages.nix** | Reading files on every eval → IFD                                                                   | Replace with `lib.cleanSourceWith` or path dependencies                        |
| **Image-based: `lib.cleanSource` with filter**                   | Full re-evaluation of src on every build                                                            | Use `lib.cleanSourceWith` with named sources                                   |
| **Dependency on nixpkgs-unstable**                               | Frequent updates → cache rebuilds                                                                   | Pin a stable version for the base system; use overlays for individual packages |

## Architectural issues

1. **Everything in one closure** — systemPackages mixes heavy, frequently changing software (rustc,
   gcc) with the base system tools. Any change triggers a system-path relink.

1. **No base/user-environment split** — home-manager or `nix profile` would let you rebuild only the
   user layer separately from the system.

1. **Many imports in `modules/default.nix`** — every import adds evaluation time (partly mitigated
   by domainFilter, which skips unused domains). Not critical.

## Recommendations

| Action                                                     | Expected effect                      | Complexity |
| ---------------------------------------------------------- | ------------------------------------ | ---------- |
| Raise `cores = 4`                                          | -15-20% build time                   | Low        |
| Enable `devSpeed` while working on the config              | Skip heavy features in test builds   | Low        |
| Move `pathExists` to CI/commit time                        | ~100 ms faster evaluation            | Medium     |
| Split systemPackages into base + heavy (via feature flags) | Fewer rebuilds when software changes | Medium     |
| Add a remote builder                                       | Offload load from the desktop        | High       |

## Rationale

- `builtins.pathExists` with absolute paths outside the repo is an impure operation. Relative paths
  inside the source tree are cached fine by nix (they are deterministic). The only impure call was
  in `session/chat.nix` — replaced with a feature flag.

- `cores = 2` vs `cores = 4`: nix runs `max-jobs` parallel builds, each with `cores` threads. With
  16 physical cores / 32 threads:

  - cores=2, max-jobs=16 → 16 parallel jobs × 2 threads = 32 threads (full utilization)
  - cores=4, max-jobs=8 → 8 parallel jobs × 4 threads = 32 threads (same utilization, but each job
    finishes faster thanks to less contention on the shared cache)
  - cores=2 → more IPC overhead between build processes

- `profile = "full"` enables every feature flag. `devSpeed = true` disables web.tools, qt, fun, ai,
  torrent — leaving the minimum needed for testing.

- A remote builder (`--builders`) moves the build of heavy derivations (rustc, gcc, webkitgtk) to
  another machine. Only the final linking of the system closure stays local.
