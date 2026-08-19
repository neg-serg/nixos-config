# Hash-Anchored File Editing (hashline) for DSH

Sources read: /tmp/mintlify-md/api_tools_hashline-edit.md;
/tmp/omo-repo/packages/omo-opencode/src/tools/hashline-edit/\*\* and
/tmp/omo-repo/packages/hashline-core/src/\*\*;
/nix/store/6f6a8cbpqzilf5lv4y6zd0gpkkm5y0mk-omp-17.3.4/share/omp/src/prompts/tools/read.md; DSH
packages @deepseek-ai/dsh-tool-fs, dsh-fs, dsh-fs-local, dsh-fs-observation-policy, dsh-tools (rc.6
checkout).

## 1. How {line}#{hash} tags integrate with DSH read output and edit validation

**Current DSH read output.** `@deepseek-ai/dsh-tool-fs/lib/index.js` renders reads in
`formatReadOutput` as an envelope:

```
<path>/abs/file.ts</path>
<type>file</type>
<content>
42: function hello() {
43:   console.log("world")
</content>
```

The JSON output schema is `{path, offset, lines:[{number,text}], totalLines}`; there is no hash
field. Lines are windows (offset/limit), capped at 2000 lines / 2000 chars per line / 50 KiB, and
streamed above 10 MiB.

**Target read format.** Omo emits `{line}#{hash}|{content}` per line; edit anchors are
`{line}#{hash}` only (never the `|content` suffix). DSH integration therefore needs one of two read
surfaces:

- **Minimal (recommended):** a fork plugin registers a new tool `read_hashline` that replicates DSH
  windowing (offset/limit/byte caps) and emits tags. The built-in `read` is untouched.
- **Full:** patch `formatReadOutput` and the `read` output schema in `dsh-tool-fs` to add `hash` to
  each line object and render `42#VK|text`. This tags the tool the model already calls.

Why the minimal route exists as a separate tool name: `dsh-tools` `ToolLayer` uses `NamedEntries`
whose insert throws on a duplicate name in the same scope (lib/index.js: “tool … is already
registered”). `dsh-tool-fs` registers `read` globally, so a fork plugin cannot re-register `read` in
the global scope; it can only add new names (or, later, shadow per-agent through `agent.ctx`
registration).

**Edit-side validation.** DSH’s current `edit` is literal `old_string` unique-match with a
provider-side stale guard:

1. `fs/edit-intent` waterfall → `dsh-fs-observation-policy` returns `{version}` of the session’s
   last `fs/observed` record (throws `FS_NOT_OBSERVED` if the file was never read).
1. `dsh-fs-local.editText` re-stats under a per-target lock and rejects when the version differs
   (`FS_STALE_VERSION`), then applies the literal replacement atomically.

`hashline_edit` keeps that version CAS and adds hash validation *before* writing:

- `read_hashline`/read emits `ctx.emit("fs/observed", target, {kind:"present", version}, exec)`.
- `hashline_edit` resolves the target, calls `ctx.waterfall("fs/write-intent", …)` (returns
  `replaceIfVersion{version}` once observed), reads the current canonical text, validates every
  anchor hash against the current lines, applies the ops in memory, then calls
  `ctx.fs.writeText(target, newContent, intent, signal, sandboxPolicy)`. The provider re-checks the
  version inside its lock, closing the TOCTOU gap between the tool’s read and its write.

Hash mismatch and version CAS are complementary: hash mismatch gives the model *corrected tags* and
a diff-like context; version CAS catches a race that happens between the tool’s validation read and
its write.

## 2. Algorithm

Per-line hash (from `hashline-core/src/hash-computation.ts`, `constants.ts`, `xxhash32.ts`):

1. **Normalize content:** `line.replace(/\r/g,"").trimEnd()` (CR stripped, trailing whitespace
   removed; leading whitespace is significant).
1. **Seed:** 0 when the line contains a Unicode letter/number (`/[\p{L}\p{N}]/u`); otherwise the
   1-based line number. Blank/whitespace-only lines therefore hash position-dependently and stay
   distinguishable.
1. **Hash:** xxHash32 over the UTF-8 bytes of the normalized line with that seed. Omo prefers the
   host runtime’s native xxHash32 and falls back to a pure-JS implementation.
1. **Map to 2 chars:** `index = hash % 256`; the 16-symbol CID alphabet is
   `NIBBLE_STR = "ZPMQVRWSNKTXJBYH"`; the tag is
   `NIBBLE_STR[index >>> 4] + NIBBLE_STR[index & 0xf]`. 16×16 = 256, so each byte maps to one tag. A
   single tag collides at ~1/256; the line number in the anchor disambiguates.

**Format:** read output `{line}#{hash}|{content}`; edit anchor `{line}#{hash}`.

**Validation (`validation.ts`):**

- `normalizeLineRef` trims, strips a leading `>>>`/`+`/`-`, collapses spaces around `#`, drops a
  `|content` suffix, then extracts an embedded `\d+#[ZPMQVRWSNKTXJBYH]{2}`. `parseLineRef` enforces
  `/^([0-9]+)#([ZPMQVRWSNKTXJBYH]{2})$/` and reports the expected format otherwise.
- Bounds check: `line < 1 || line > lines.length` → error with the file’s line count.
- Hash check: recompute and compare. **Compatibility rule** `isCompatibleLineHash` accepts the
  modern hash *or* the legacy hash (same computation but `.replace(/\s+/g,"")` —
  whitespace-insensitive). That is the “autocorrect on shifts”: a line whose indentation changed
  still validates under its old tag.
- All refs are validated against one snapshot before any mutation, then edits are ordered bottom-up
  (descending line number) so earlier line numbers stay valid, and overlapping replace ranges are
  rejected.
- **Mismatch rejection:** collect every mismatch, throw `HashlineMismatchError` whose `remaps` maps
  `old "line#hash"` → `new "line#hash"`, and whose message shows ±2 context lines with the
  recomputed tags, marking changed lines with `>>>`. `suggestLineForHash` additionally finds a moved
  line whose content matches the supplied hash and proposes its current reference.

**Content autocorrect (apply-time, from `autocorrect-replacement-lines.ts` /
`edit-text-normalization.ts`):** strip `>>>`/hashline prefixes and `+` diff markers from inserted
text; strip boundary-echo lines that duplicate adjacent surviving lines; restore leading indentation
from the replaced line; expand a single merged line back to the original line count; preserve BOM
and CRLF via `canonicalizeFileText/restoreFileText`. These do not move anchors — anchor shifts are
surfaced as remaps, not silently guessed.

## 3. Feasibility verdict

| Level                        | Verdict                                                                                                                                                                                                                                                                                                                                                                                                   |
| ---------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Client plugin (fork package) | **Recommended.** Registers `read_hashline` + `hashline_edit` as new tool names (no `read` conflict), reuses `ctx.fs`, `ctx.waterfall("fs/write-intent")`, `ctx.emit("fs/observed")`, and the `dsh-sandbox` escalation schema pattern. Lives in the `dsh-web-ui` fork under `packages/dsh-hashline/`, wired by the `TUI_FORK` symlink pattern; F5/hot-reload applies (per docs/howto/dsh-web-forks.ru.md). |
| Fork patch (`dsh-tool-fs`)   | Needed **only** to put tags inside the built-in `read`. That is a first-party upstream bundle shipped via the Nix `packages/dsh/web-ui-en` scope symlink; patching it means a build-time/scope-level override and re-doing it on upstream upgrades. Optional phase 2.                                                                                                                                     |
| Server patch                 | Not required for the edit tool. The only server-side change would again be the `read` render; same cost as the fork patch, worse for upgrades.                                                                                                                                                                                                                                                            |

**Effort.** MVP: 1.5–3 days — `read_hashline` windowing/tagging + `hashline_edit` (replace
single/range, append, prepend; `lines` as string|string[]; hash validation + remap error; version
CAS; LF/CRLF+BOM restore; sandbox fields). Full parity with omo (dedupe, full autocorrect suite,
overlap diagnostics, rename/delete, formatter trigger, diff metadata card, per-agent `read` shadow,
tests): 5–10 days.

**Minimal viable version.** One fork package with two tools:

- `read_hashline`: `file_path`, `offset`, `limit` → bounded `{line}#{hash}|{content}` blocks +
  `fs/observed` present observation.
- `hashline_edit`: `file_path`, `edits[{op:"replace"|"append"|"prepend", pos?, end?, lines}]`,
  optional sandbox escalation fields. Pipeline: resolve → write-intent → read canonical text →
  normalize edits → collect/validate refs (modern+legacy hash) → overlap check → bottom-up sort →
  apply → restore BOM/CRLF → `writeText` with `replaceIfVersion` → `fs/observed` new version →
  return updated-path confirmation (and diff meta).

Deferred until after MVP: tagging the built-in `read`, delete/rename, formatter triggers, full
autocorrect, dedupe reporting.

## 4. TypeScript prototype (tag generation + validation)

```ts
// Self-contained; no deps beyond TextEncoder/globalThis.

const NIBBLE_STR = "ZPMQVRWSNKTXJBYH";
const DICT: string[] = Array.from({ length: 256 }, (_, i) =>
  NIBBLE_STR[i >>> 4] + NIBBLE_STR[i & 0xf]
);
const REF_RE = /^([0-9]+)#([ZPMQVRWSNKTXJBYH]{2})$/;
const EMBED_RE = /([0-9]+#[ZPMQVRWSNKTXJBYH]{2})/;
const SIGNIFICANT_RE = /[\p{L}\p{N}]/u;

// --- xxHash32 (pure JS fallback) ---
const P1 = 0x9e3779b1, P2 = 0x85ebca77, P3 = 0xc2b2ae3d, P4 = 0x27d4eb2f, P5 = 0x165667b1;
function rotl(x: number, b: number): number { return ((x << b) | (x >>> (32 - b))) >>> 0; }
function rd32(b: Uint8Array, o: number): number {
  return ((b[o] ?? 0) | ((b[o+1] ?? 0) << 8) | ((b[o+2] ?? 0) << 16) | ((b[o+3] ?? 0) << 24)) >>> 0;
}
function round(acc: number, v: number): number {
  return Math.imul(rotl((acc + Math.imul(v, P2)) >>> 0, 13), P1) >>> 0;
}
function xxh32(input: string, seed: number): number {
  const data = new TextEncoder().encode(input);
  let off = 0; const len = data.length; let h: number;
  if (len >= 16) {
    const limit = len - 16;
    let v1 = (seed + P1 + P2) >>> 0, v2 = (seed + P2) >>> 0, v3 = seed >>> 0, v4 = (seed - P1) >>> 0;
    while (off <= limit) {
      v1 = round(v1, rd32(data, off)); off += 4;
      v2 = round(v2, rd32(data, off)); off += 4;
      v3 = round(v3, rd32(data, off)); off += 4;
      v4 = round(v4, rd32(data, off)); off += 4;
    }
    h = (rotl(v1, 1) + rotl(v2, 7) + rotl(v3, 12) + rotl(v4, 18)) >>> 0;
  } else {
    h = (seed + P5) >>> 0;
  }
  h = (h + len) >>> 0;
  while (off + 4 <= len) { h = (h + Math.imul(rd32(data, off), P3)) >>> 0; h = Math.imul(rotl(h, 17), P4) >>> 0; off += 4; }
  while (off < len) { h = (h + Math.imul(data[off] ?? 0, P5)) >>> 0; h = Math.imul(rotl(h, 11), P1) >>> 0; off += 1; }
  h ^= h >>> 15; h = Math.imul(h, P2) >>> 0; h ^= h >>> 13; h = Math.imul(h, P3) >>> 0; h ^= h >>> 16;
  return h >>> 0;
}

// --- hash computation ---
function normalized(line: string): string { return line.replace(/\r/g, "").trimEnd(); }
function legacy(line: string): string { return line.replace(/\r/g, "").replace(/\s+/g, ""); }

export function computeLineHash(lineNumber: number, content: string): string {
  const s = normalized(content);
  const seed = SIGNIFICANT_RE.test(s) ? 0 : lineNumber;
  return DICT[xxh32(s, seed) % 256];
}
export function computeLegacyLineHash(lineNumber: number, content: string): string {
  const s = legacy(content);
  const seed = SIGNIFICANT_RE.test(s) ? 0 : lineNumber;
  return DICT[xxh32(s, seed) % 256];
}
export function formatHashLine(lineNumber: number, content: string): string {
  return lineNumber + "#" + computeLineHash(lineNumber, content) + "|" + content;
}

// --- reference parsing / normalization ---
export interface LineRef { line: number; hash: string }

export function normalizeLineRef(raw: string): string {
  let t = raw.trim();
  t = t.replace(/^(?:>>>|[+-])\s*/, "");
  t = t.replace(/\s*#\s*/, "#");
  t = t.replace(/\|.*$/, "");
  t = t.trim();
  if (REF_RE.test(t)) return t;
  const m = t.match(EMBED_RE);
  return m ? m[1] : raw.trim();
}
export function parseLineRef(ref: string): LineRef {
  const n = normalizeLineRef(ref);
  const m = n.match(REF_RE);
  if (m) return { line: Number(m[1]), hash: m[2] };
  throw new Error('Invalid line reference format: "' + ref + '". Expected "{line_number}#{hash_id}"');
}

// --- validation with mismatch rejection + remaps ---
export class HashlineMismatchError extends Error {
  readonly remaps: ReadonlyMap<string, string>;
  constructor(private mismatches: {line:number; expected:string}[], private lines: string[]) {
    super(formatMismatch(mismatches, lines));
    this.name = "HashlineMismatchError";
    const remaps = new Map<string, string>();
    for (const mm of mismatches) {
      const actual = computeLineHash(mm.line, lines[mm.line - 1] ?? "");
      remaps.set(mm.line + "#" + mm.expected, mm.line + "#" + actual);
    }
    this.remaps = remaps;
  }
}
function compatible(line: number, content: string, hash: string): boolean {
  return computeLineHash(line, content) === hash || computeLegacyLineHash(line, content) === hash;
}
function formatMismatch(mismatches: {line:number; expected:string}[], lines: string[]): string {
  const byLine = new Map(mismatches.map(m => [m.line, m]));
  const shown = new Set<number>();
  for (const m of mismatches) for (let l = Math.max(1, m.line - 2); l <= Math.min(lines.length, m.line + 2); l++) shown.add(l);
  const out: string[] = [
    mismatches.length + (mismatches.length === 1 ? " line has" : " lines have") +
    " changed since last read. Use updated {line_number}#{hash_id} references below (>>> marks changed lines).", ""
  ];
  let prev = -1;
  for (const l of [...shown].sort((a,b) => a-b)) {
    if (prev !== -1 && l > prev + 1) out.push("    ...");
    prev = l;
    const line = lines[l - 1] ?? "";
    const tag = l + "#" + computeLineHash(l, line) + "|" + line;
    out.push((byLine.has(l) ? ">>> " : "    ") + tag);
  }
  return out.join("\n");
}
export function validateLineRefs(lines: string[], refs: string[]): void {
  const mismatches: {line:number; expected:string}[] = [];
  for (const ref of refs) {
    const { line, hash } = parseLineRef(ref);
    if (line < 1 || line > lines.length) {
      const hint = suggestLineForHash(ref, lines);
      throw new Error("Line number " + line + " out of bounds (file has " + lines.length + " lines)" + (hint ? " " + hint : ""));
    }
    if (!compatible(line, lines[line - 1], hash)) mismatches.push({ line, expected: hash });
  }
  if (mismatches.length > 0) throw new HashlineMismatchError(mismatches, lines);
}
function suggestLineForHash(ref: string, lines: string[]): string | null {
  const m = ref.trim().match(/#([ZPMQVRWSNKTXJBYH]{2})$/);
  if (!m) return null;
  for (let i = 0; i < lines.length; i++) {
    if (compatible(i + 1, lines[i], m[1])) {
      return 'Did you mean "' + (i + 1) + "#" + computeLineHash(i + 1, lines[i]) + '"?';
    }
  }
  return null;
}
```

The apply layer (normalize edits → collect refs → `validateLineRefs` → overlap check → bottom-up
sort → splice) is lifted unchanged from `hashline-core/src/edit-operations.ts` and is not repeated
here; the generation and validation above are the DSH-specific pieces.

______________________________________________________________________

**Primary outputs.** This design is written to `/tmp/subagent-out/hashline.md`. No repo files were
modified.
