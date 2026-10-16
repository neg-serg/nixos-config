# PR bodies

One block per patch, ready to paste. Commit subjects follow the repo's own style (`derivation:`,
`builtins:`, `flake:`, `store:`, `fetchers:`).

______________________________________________________________________

## 01 — `derivation: escape control characters in structured-attrs JSON`

Fixes #61.

`appendJsonString` escaped only `"`, `\`, `\n`, `\r` and `\t`; every other byte below `0x20` went
into `__json` raw, which is not valid JSON. The daemon parses that attribute with a strict reader,
so one ESC byte — a coloured snippet in an activation script or a build command is enough — rejected
the whole derivation:

```
error: daemon: cannot process __json attribute:
[json.exception.parse_error.101] ... invalid string: control character U+001B (ESC)
must be escaped to \u001B
```

The escape is now complete: `\b` and `\f` get their short forms, every other control byte becomes
`\u00xx`, matching what Nix's own JSON writer emits.

The pure helper `appendEscapedJsonString` (the writer itself) is unit-testable, so the test asserts
both the escaping and that `std.json.validate` accepts the result. `zig build test-expr` passes.

The escaping is hand-rolled to keep the diff small; if you would rather route it through
`std.json.Stringify.encodeJsonString`, I am happy to rework it that way.

Boundary I did not change: bytes ≥ 0x20 are still copied through, so invalid UTF-8 stays invalid
JSON (Nix refuses it earlier, in its own writer). Control bytes and valid UTF-8 are byte-identical
to Nix — the derivation path of a probe with every control byte in an attribute matches Nix's own
`.drvPath`.

______________________________________________________________________

## 02 — `builtins: omit pure-gated constants the way Nix does`

Fixes #53.

In pure evaluation Nix does not *gate* `builtins.currentSystem` and `builtins.currentTime` — the
attributes are **absent**:

```console
$ nix --pure-eval eval -E 'builtins ? currentSystem'
false
```

This evaluator kept them present and raised on access, so the flake-compat guard
`!builtins ? currentSystem || …` took the wrong branch and configurations that work under Nix failed
here.

`buildAttrSet` now takes the policy and omits both attributes in pure mode, and `setPureEval` clears
the cached `builtins` attrset — the cache was populated before the policy was known (CLI flake-ref
resolution evaluates first), which is why the fix would otherwise appear not to work.

Tests: `builtins ? currentSystem` is false in pure mode, and flipping the policy after a first
evaluation rebuilds the attrset.

______________________________________________________________________

## 03 — `builtins: make pure-eval search-path gates catchable`

Addresses #52.

Two Nix behaviours that nixpkgs depends on:

1. `builtins.nixPath` is `[]` in pure mode and a `<name>` lookup fails with a *catchable* "not
   found" — it is not an uncatchable gate. nixpkgs' `pkgs/top-level/impure-overlays.nix` does
   `try (toString <nixpkgs-overlays>) ""` under `tryEval`; with an uncatchable gate the raised error
   escapes `tryEval` and aborts the whole evaluation.
1. `builtins.pathExists` on a path the policy does not allow answers `false` instead of raising
   (Nix's string→path coercion fails silently there).

`builtinFindFile` no longer calls the pure-eval gate, `purity.enforceNoSearchPath` is gone, and
`pathExists` maps the restriction to `false`; reading such a path is still an error.

The existing pure-eval test asserted the old behaviour, so it now asserts the catchable lookup, and
a dedicated test covers the empty `builtins.nixPath`, the `tryEval (toString <nixpkgs-overlays>)`
probe, `pathExists` outside the allowed roots and the still-importable `<nix/fetchurl.nix>`.

Verified: `zig build test-expr` — 543 passed, 5 skipped, 0 failed.

An alternative would be to keep the gate and make it *catchable* instead of removing it; this patch
follows Nix — an empty search path and `false` from `pathExists` — because that is the observable
behaviour nixpkgs already relies on (the `tryEval` probe above).

An explicit list is not a loophole: its bases, and the resolved candidate (so a `name` cannot walk
out with `..`), go through the same read confinement, so
`builtins.findFile [{ prefix = ""; path = "/etc"; }] "hostname"` is refused instead of answered. An
independent verification pass found that case in an earlier revision of this patch; the test now
covers it.

______________________________________________________________________

## 04 — `flake: resolve bare git work-tree roots as git refs`

Related to #55.

Nix treats a bare path inside a git work tree as `git+file`: the flake source is the tracked (plus
dirty-tracked) content of the repository. Resolving it as a plain directory instead copies whatever
sits in the tree — `.git`, caches, build output — into the store. On a real repository that is both
wrong and fatal: a 283 MiB cache blob under an ignored directory tripped the file reader's 128 MiB
cap and the command died with `error: StreamTooLong`.

The resolver now emits a `git+file` ref for a work-tree root (only where the ref already names an
existing directory, and only when writes to the store are enabled — plain `eval` still reads the
directory in place, as before).

Test: a bare path that is a work-tree root resolves to a git ref and exposes only tracked files; a
repository with an **unborn HEAD** (`git init`, nothing committed) keeps the plain `path` behaviour,
because there is no revision to fetch there and that case used to work. Only a HEAD that proves
resolvable takes the git route (a symbolic ref that exists loose or in `packed-refs`, or a full
40-hex detached id); empty, garbage, missing or symlinked HEADs fall back to the directory copy too.

Nix's own flake layer does fetch an unborn HEAD as `git+file` (lastModified 1970); the fallback here
is deliberate — the git transport has no revision to fetch. If you would rather support unborn
checkouts on the git side, that is a separate change and I am happy to look at it.

One parity note for you to decide on: `nix flake metadata <work-tree>` resolves as `git+file://…`,
while `builtins.parseFlakeRef`/`getFlake` in Nix 3.21.7 answer `{ type = "path"; }` for the same
directory. This patch follows the flake installable (and only when the tree is written to the store
— plain `eval` keeps the `path` answer), so with store writes the *builtin* now differs from Nix's
builtin. Happy to restrict the change to the installable path if you prefer that shape.

______________________________________________________________________

## 05 — `store: name the file that exceeds the read cap`

`readFileAlloc(..., .limited(max_read_bytes))` returned a bare `StreamTooLong` that said nothing
about *which* file was too large, in a code path reached from `builtins.readFile`, from NAR
serialization and from store ingestion. On a real tree this is the difference between a one-line fix
(exclude or stream that file) and bisecting a whole configuration.

The cap now reports the offending path:

```
fix: file-read cap (128 MiB) exceeded by /home/user/src/demo/Renoise_3_5_4_Demo_Linux_x86_64.tar.gz
error: StreamTooLong
```

No behaviour change beyond the message. It goes to stderr through `std.debug.print`, the shape the
rest of the tree uses for diagnostics (`runtime/gc.zig`, `cli/*`, `expr/*`); if you would rather
carry the path inside the error value, say so and I will rework it.

______________________________________________________________________

## 06 — `store: stream files above the read cap through the NAR writer`

Companion to the large-file issue. With the diagnostic in place, the failing read turned out to be
the NAR serializer ingesting a source tree: `writeNode` read regular files whole, so one blob above
`FileCache.max_read_bytes` aborted the ingest of an entire tree (a `path:` input containing a 200
MiB tarball was enough).

`writeFileContents` now stats the file: at or below the cap it keeps the cached read, above it
streams in 64 KiB chunks with the length prefix written from the stat and the trailing NAR padding
preserved — the serialized bytes are identical and Nix (which streams every file) produces the same
NAR.

On memory, to be precise: the file is no longer materialized on the heap — with a counting allocator
a 4 MiB file peaks at 384 bytes streamed versus 6.3 MB via the cached read — while the NAR buffer
itself is unchanged (`serializeCapped` still accumulates the archive; only `hashPathDigestFiltered`
streams end to end).

The threshold is now a parameter of the internal serializer (`serializeCapped`;
`serialize`/`serializeReport` keep the cache's cap as the default), so the streaming branch is
testable without a 128 MiB allocation: the test serializes a 205-byte file with a 64-byte cap and
asserts the result is byte-identical to the cached read's, which covers the length prefix and the
non-multiple-of-8 padding (`zig build test-store` passes).

I would still like the maintainer's view on the alternative — a configurable cap instead of
streaming — before this lands.

______________________________________________________________________

## 07 — `fetchers: fall back to the system git when the built-in client cannot fetch`

New issue (see `issues/01-kernel-org-fetch.md`). The built-in git client cannot fetch a pinned
shallow revision from `git.kernel.org` (GitHub and Codeberg work), while `git` itself fetches the
same revision fine — which is also what Nix does: its git fetcher shells out to `git`.

The transport now falls back to the system `git` when the built-in fetch fails at the transport
level, with the same refspecs the client would have used (`+<rev>:refs/remotes/origin/pinned`,
branch or tag refspecs, `--depth 1` when shallow), and reopens the cache repository so the following
resolve/checkout sees the new pack files. A missing `git` and a non-zero exit both keep the original
`FetchGitFailed`.

The fallback binary is a new `Options` field, `git_fallback_bin` (default `"git"`); `null` disables
the fallback entirely, which is also the shape an opt-in flag would take.

The test is landed and fully offline: it points `git_fallback_bin` at a stub script, lets the
built-in fetch fail against a closed port (`http://127.0.0.1:1/repo.git`,
`connect_timeout_seconds = 1`) and asserts the stub received
`fetch --depth 1 <url> +<rev>:refs/remotes/origin/pinned` (`zig build test-fetchers` passes).

Failure paths are covered as well: the external fetch runs *before* the open repository handle is
dropped, and the replacement is opened before the old one goes away, so a failing system `git`
(missing binary or non-zero exit) reports the error and leaves the cache repository usable. An
earlier revision deinited the repository twice on that path and segfaulted — found by the same
independent verification pass, now a regression test.

Open questions for the maintainer:

1. Is a subprocess fallback acceptable here at all, or would you rather see the client fixed for
   that server? (The other adapters already shell out for hg, ssh and tar, but the git path was
   deliberately pure.)
1. Should the default be `null` (opt-in) rather than `"git"`?
