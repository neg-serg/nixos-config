# /nix Deduplication Benchmark (Borg + VDO model)

This note records how we estimated potential block-level deduplication
and compression savings for `/nix`.  It doubles as a recipe for repeating the
experiment whenever the store grows significantly.

## Background

- **VDO** (Virtual Data Optimizer) is a device-mapper target that intercepts
  4 KiB blocks, fingerprints them, and stores only one copy.  Matching blocks
  across files point back to the same physical extent, and the remaining unique
  blocks optionally go through a built-in LZ4-style compressor.  The end result
  is “dedupe + compression” at the block layer.
- **Borg** is a deduplicating backup tool that can emulate the same workflow:
  we can force a fixed chunk size (`--chunker-params fixed,4096`) so every
  4 KiB block is hashed exactly once, and we can toggle `--compression none|lz4`
  to measure “dedupe only” vs. “dedupe + compression”.
  Although Borg normally targets archive backups, here it is a measurement tool.

Running this benchmark helps decide whether enabling VDO/btrfs/ZFS dedup is
worth the additional RAM/CPU cost.  The absolute numbers also provide a rough
upper bound for possible space reclamation.

## How the test was run

1. Create a temporary Borg repository on a large, writable disk
   (`/zero/caches/nix-dedupe-borg` was used in this run).

2. Collect stats with fixed 4 KiB chunks, first without compression, then with
   LZ4:

   ```bash
   # Dedup only (closely mimics VDO without compression)
   borg init --encryption=none /zero/caches/nix-dedupe-borg
   borg create --stats --json \
     --compression none \
     --chunker-params fixed,4096 \
     /zero/caches/nix-dedupe-borg::nix-$(date +%Y%m%d%H%M%S) /nix

   # Delete repo, repeat with compression to emulate VDO fully
   borg delete /zero/caches/nix-dedupe-borg
   borg init --encryption=none /zero/caches/nix-dedupe-borg
   borg create --stats --json \
     --compression lz4 \
     --chunker-params fixed,4096 \
     /zero/caches/nix-dedupe-borg::nix-$(date +%Y%m%d%H%M%S) /nix
   ```

   Notes:

   - Run as a user who can read `/nix`.  A few lock files under
     `/nix/var/nix/{builds,gc.lock,db,temproots,userpool}` are root-only (a few
     KB) and were skipped; they do not alter the totals materially.
   - Each pass took ~11–14 minutes on this host and produced a repository
     between 65–120 GiB.  Clean up with `borg delete …` when finished.

3. Parse the JSON stats (`original_size`, `deduplicated_size`,
   `compressed_size`) to convert them to GiB/percentages.

## November 2025 results

| Run | Borg flags | Original size | Logical unique data | Repo size on disk | Savings |
| --- | ---------- | ------------- | ------------------- | ----------------- | ------- |
| Dedup only | `--compression none --chunker-params fixed,4096` | 176 302 987 003 B (≈164.19 GiB) | 122 781 869 773 B (≈114.35 GiB) | 122 781 869 773 B | ≈49.85 GiB saved (≈30.4 %) |
| Dedup + LZ4 | `--compression lz4 --chunker-params fixed,4096` | same as above | 67 008 764 776 B (≈62.41 GiB) | 89 704 670 309 B compressed → 67 008 764 776 B stored | ≈101.79 GiB saved (≈62.0 %) |

Interpretation:

- A pure block-level dedupe layer could reclaim roughly one third of the `/nix`
  footprint.
- Adding lightweight compression after dedupe (the default in VDO) nearly
  doubles the savings because many Nix store paths compress very well.

## Why keep this test handy?

- **Capacity planning**: provides a concrete upper bound on potential savings
  before committing to a dedupe layer that consumes RAM/CPU.
- **Change tracking**: re-running later shows whether the dedupe ratio drifts
  as the store grows, which helps estimate when to expand disks.
- **Tool validation**: confirms Borg is present on the host and that
  `/zero/caches` has enough free space for future audits.

Delete the repository once the numbers are recorded:

```bash
yes YES | borg delete /zero/caches/nix-dedupe-borg
```

Recreate it if another snapshot is needed.  All temporary data belongs under
`/zero/caches` to avoid filling `/`.
