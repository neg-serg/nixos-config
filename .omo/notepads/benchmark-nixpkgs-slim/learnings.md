# benchmark-nixpkgs-slim learnings

## Upstream equivalent commit

- **Target timestamp**: `1784085041` (2026-07-15 03:10:41 UTC)
- **UPSTREAM_REV**: `18b9261cb3294b6d2a06d03f96872827b8fe2698`
- **Commit date**: `2026-07-14T05:44:30Z` (1784007870)
- **Diff**: 77171s (~21h 26m) — outside the 1h window
- **Note**: Script hit GitHub API rate limit (403), fell back to `git ls-remote` of `refs/heads/nixos-unstable`. Primary API query (with `until=` parameter) returns the same SHA — this is the latest commit on `nixos-unstable` before the target timestamp. No commits landed in the 21h window preceding the target.
