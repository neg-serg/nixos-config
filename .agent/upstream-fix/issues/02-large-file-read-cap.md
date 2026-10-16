# Issue draft: one file above the 128 MiB read cap aborts a whole tree ingest

**Title:** A file larger than the 128 MiB read cap makes tree ingestion (and pure `readFile`) fail
with a bare `StreamTooLong`

## What happens

Ingesting a source tree that contains one file above the cap aborts the whole operation:

```console
$ fix build --flake /etc/nixos#nixosConfigurations.<host>.config.system.build.toplevel
error: StreamTooLong
```

with a trace ending in the module that consumes the path input. In our case the offending file was a
200 MiB tarball inside a `path:` flake input
(`/home/user/nixos-src/renoise/Renoise_3_5_4_Demo_Linux_x86_64.tar.gz`); a bare work-tree path
containing a 283 MiB cache blob failed the same way.

## Where it comes from

- `src/store/file_cache.zig`: `max_read_bytes = 128 * 1024 * 1024`, applied by
  `readFile`/`retainFile` through `.limited(max_read_bytes)`.
- Those whole-file reads are used both by `builtins.readFile` and by `src/store/nar.zig`'s
  `writeNode`, i.e. by NAR serialization of a tree — so the cap is not a "this single read is
  suspicious" guard in that path, it decides whether a *tree* can be ingested at all.
- The error names no file: `StreamTooLong` on its own gives no way to tell which blob tripped it,
  and on a large tree bisecting that is expensive.

## Why I think it should change

Nix streams files while serializing a NAR and has no such cap, so a configuration that Nix builds
and activates aborts here. Trees with big blobs are not exotic: vendored tarballs, demo/asset
archives, generated firmware images.

## Proposal

Two small patches, in this order:

1. Name the offending path in the message (no behaviour change):
   `fix: file-read cap (128 MiB) exceeded by <path>`.
1. Stream files above the cap in the NAR writer: stat the file, write the length from the stat, copy
   in bounded chunks, keep the NAR padding — the serialized bytes are unchanged, memory stays
   bounded.

## Questions

1. Would you rather keep a hard cap and offer an option to raise it, instead of streaming?
1. Is the 128 MiB value load-bearing anywhere (e.g. a fuzz/robustness decision), in which case the
   cap should stay for `builtins.readFile` and only the NAR writer should stream?
