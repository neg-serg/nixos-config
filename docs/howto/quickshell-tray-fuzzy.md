# Tray menu search: fuzzy filtering and match highlighting

The menu search box (tray menus, Hiddify's menu, nested submenus) ranks entries with the same
algorithm as the Lusty pickers and marks the matched letters. Both come from one implementation:
the `lusty-fuzzy` crate in the lusty repo, and a JS port of it in this tree.

## Pieces

| Piece | Where | Role |
| --- | --- | --- |
| Matcher (source of truth) | lusty: `crates/lusty-fuzzy` | scoring, spans, ranking policy, RU→EN table |
| Vector dump | `lusty --fuzzy-vectors --corpus <file>` | JSON ranking of a corpus, the oracle for ports |
| Port | `files/quickshell/Helpers/Fuzzy.js` | the marcher the tray calls |
| Fixture | `files/quickshell/Helpers/tests/fuzzy-vectors.json` | generated oracle, committed |
| Gate | `scripts/dev/check-fuzzy-parity.sh` (+ `.mjs`) | replays the fixture against the port |
| Regenerate | `scripts/dev/gen-fuzzy-vectors.sh` | rewrites the fixture from a lusty binary |

The port is a port, not a wrapper around a subprocess: a menu re-ranks on every keystroke, and
spawning a helper per keystroke (plus its lifecycle) costs more than the scoring itself for the
tens-to-hundreds of labels a menu holds. `lusty serve`'s query path stays available if a list ever
grows past that.

## What the tray does differently from the file pickers

The math is shared; the policy is not:

- **No first-letter anchor.** `RankOpts::for_files()` requires the query's first character to be a
  prefix of the basename (`c` must not match `pic.jpg`). In a menu that is wrong: `b` has to find
  "Open in browser". The tray ranks with `anchor: "none"`.
- **Unicode case folding.** Menu labels arrive localized from apps, so folding is Unicode-wide
  here (`to_Lowercase()`/`toLowerCase()`), while the pickers keep the historical ASCII-only
  folding.
- **Wrong-layout queries are merged, not ignored.** A query typed in the RU layout is also ranked
  as its EN reading, and both readings are merged (better score per label wins). A literal
  Cyrillic query therefore still finds Cyrillic labels — the fixture pins this case.
- **Mnemonic markers.** DBus menu labels carry accelerators (`&File` from Qt, `_Open` from GTK).
  Matching uses `Fuzzy.stripMnemonic()`; the label drawn on screen keeps the original text.

## Match highlighting

`Fuzzy.rank()` returns byte spans (the matcher works on UTF-8 bytes, like Rust).
`Fuzzy.highlightMarkup(label, spans, css)` converts them to string ranges and returns escaped
rich text with the matched runs wrapped, which `Components/DelegateEntry.qml` feeds to its label.
Two consequences worth knowing:

- The label is drawn as rich text only while a query is active. Qt elides plain text only, so
  during a search the label is clipped instead of elided.
- Spans address the label the UI drew, not a case-folded copy of it: the folding path keeps a
  byte-offset map and maps the spans back.

## Keeping the port honest

`scripts/dev/check-fuzzy-parity.sh` (wired into `just lint`) does two things:

1. replays `fuzzy-vectors.json` against `Fuzzy.js` and fails on any difference in result count,
   order, score (1e-9) or spans; also checks the port's internal invariants (the lean scorer and
   the span extractor must agree; escaping and byte→string mapping of the markup helper);
2. when the deployed `lusty` has `--fuzzy-vectors`, re-derives the fixture from the crate and
   compares byte for byte, so a crate change cannot leave a stale fixture behind. The deployed
   binary is probed with `strings`, never executed: an older lusty would treat the unknown flag as
   a path and drop into its TUI.

When the crate's scoring, span extraction or ranking policy changes: bump `WEIGHTS_VERSION`, run
`scripts/dev/gen-fuzzy-vectors.sh` (with `LUSTY_SRC` pointing at the checkout), and commit the new
fixture together with the crate change. The gate fails on a mismatch instead of silently ranking
with two different algorithms.
