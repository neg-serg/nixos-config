#!/usr/bin/env node
/**
 * dsh-tianshu-tui — Russian UI patch (idempotent).
 *
 * The Tianshu TUI bundle (`@huiliyi37/dsh-tianshu-tui`) hardcodes its UI
 * strings in Chinese with no language switch. This patcher swaps the exact
 * string literals listed in the translation map (i18n.json) for Russian
 * ones, in place, after verifying each key actually occurs.
 *
 * Usage: node patch.mjs <i18n.json> <bundle-lib/index.js>
 *
 * Safety:
 *  - idempotent: a marker file (.dsh-tui-ru.json next to the package) records
 *    the map + bundle hashes, so already-patched bundles are skipped;
 *  - keys that do not occur in this bundle version are skipped with a warning
 *    (the map may cover a slightly different version);
 *  - if any applied key is still present after replacement, the bundle is
 *    left untouched and the patcher exits non-zero;
 *  - the pristine bundle is backed up once as index.js.orig.
 */
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";

function log(msg) {
  console.error(`[dsh-tui-ru] ${msg}`);
}

const [mapPath, bundlePath] = process.argv.slice(2);
if (!mapPath || !bundlePath) {
  log("usage: node patch.mjs <i18n.json> <bundle-lib/index.js>");
  process.exit(2);
}

const mapRaw = fs.readFileSync(mapPath, "utf8");
let map;
try {
  map = JSON.parse(mapRaw);
} catch (e) {
  log(`cannot parse translation map: ${e.message}`);
  process.exit(1);
}
const mapSha = crypto.createHash("sha256").update(mapRaw).digest("hex");

/**
 * Count string literals that still contain CJK after patching. A bundle that
 * keeps hundreds of them means the map no longer matches (e.g. the plugin was
 * upgraded upstream) — the silent failure mode that leaves a Chinese UI.
 * @param text - the patched bundle text.
 * @returns the number of distinct CJK-bearing literals.
 */
function remainingCjkLiterals(text) {
  // Comment lines keep their Chinese (invisible to the user): a leftover there
  // is not a gap, so only code lines count.
  const code = text.split("\n").filter((line) => {
    const t = line.trim();
    return !(t.startsWith("//") || t.startsWith("*") || t.startsWith("/*"));
  }).join("\n");
  const dq = /"[^"\n]*[\u4e00-\u9fff][^"\n]*"/g;
  const tpl = /`[^`\n]*[\u4e00-\u9fff][^`\n]*`/g;
  return new Set([...code.matchAll(dq)].map((m) => m[0]).concat([...code.matchAll(tpl)].map((m) => m[0]))).size;
}

/**
 * Code-level fixes this repo needs on top of the translations. Each entry is an
 * exact literal occurrence in the bundle: `from` is what upstream ships, `to`
 * what this deployment needs. Applied before the map, so `bundleSha` below
 * still records the pristine input.
 *
 * Insert-style entries (the host-compat ones) leave `from` in place, so the
 * from/to pair cannot tell an applied bundle from a pristine one — they carry
 * `probe`, a marker substring that lands in the bundle exactly once and is
 * checked first in the loop below.
 */
const FIXES = [
  {
    id: "tui-default-preset",
    from: 'const DEFAULT_PRESET_ID = "standard";',
    to: 'const DEFAULT_PRESET_ID = "neg";',
  },
  {
    id: "truncation-marker-russian",
    // The regex parses the marker back out of already-rendered lines; the
    // translated markers are Russian, so they have to match too.
    from: "/…\\s*\\+\\s*\\d+\\s*行(?:\\s*·\\s*ctrl\\+o\\s*展开)?|…\\s*\\+\\s*\\d+\\s*行 diff|…\\s*\\+\\s*\\d+\\s*lines\\s*\\[Ctrl\\+O\\]/i",
    to: "/…\\s*\\+\\s*\\d+\\s*行(?:\\s*·\\s*ctrl\\+o\\s*展开)?|…\\s*\\+\\s*\\d+\\s*行 diff|…\\s*\\+\\s*\\d+\\s*lines\\s*\\[Ctrl\\+O\\]|…\\s*(?:выше|ещё)\\s*\\d+\\s*строк|скрыто(?:\\s+выше)?\\s*\\d+\\s*строк/i",
  },

  {
    id: "cjk-\u76ee\u6807\u5df2\u963b\u585e",
    from: "`\u76ee\u6807\u5df2\u963b\u585e: ${goals.block(agent, ref, {",
    to: "`\u0426\u0435\u043b\u044c \u0437\u0430\u0431\u043b\u043e\u043a\u0438\u0440\u043e\u0432\u0430\u043d\u0430: ${goals.block(agent, ref, {",
  },
  {
    id: "cjk-\u5df2\u4fdd\u5b58\u8bb0\u5fc6",
    from: "`\u5df2\u4fdd\u5b58\u8bb0\u5fc6: ${(await memory.save({",
    to: "`\u041f\u0430\u043c\u044f\u0442\u044c \u0441\u043e\u0445\u0440\u0430\u043d\u0435\u043d\u0430: ${(await memory.save({",
  },
  {
    id: "usage-2",
    from: "const USAGE_TEXT = `dsh-tianshu-tui \u2014 DeepSeek Harness \u4ea4\u4e92\u5f0f\u7ec8\u7aef\u754c\u9762 / interactive terminal UI",
    to: "const USAGE_TEXT = `dsh-tianshu-tui \u2014 DeepSeek Harness interactive terminal UI",
  },
  {
    id: "usage-3",
    from: "\u7528\u6cd5 / Usage:",
    to: "Usage:",
  },
  {
    id: "usage-4",
    from: "  dsh --profile tui                   \u542f\u52a8\u4ea4\u4e92\u5f0f TUI / start the interactive TUI",
    to: "  dsh --profile tui                   start the interactive TUI",
  },
  {
    id: "usage-5",
    from: "  dsh --profile tui \"<\u043f\u0440\u043e\u043c\u043f\u0442>\"        \u542f\u52a8\u5e76\u76f4\u63a5\u53d1\u9001\u63d0\u793a\u8bcd / start and send a prompt",
    to: "  dsh --profile tui \"<\u043f\u0440\u043e\u043c\u043f\u0442>\"        start and send a prompt",
  },
  {
    id: "usage-6",
    from: "  dsh --profile tui --help            \u663e\u793a\u672c\u5e2e\u52a9 / show this help",
    to: "  dsh --profile tui --help            show this help",
  },
  {
    id: "usage-7",
    from: "  dsh --profile tui --version         \u8f93\u51fa\u7248\u672c / print the version",
    to: "  dsh --profile tui --version         print the version",
  },
  {
    id: "usage-8",
    from: "\u5feb\u6377\u952e / Keys: ctrl+n \u65b0\u4f1a\u8bdd \u00b7 ctrl+s \u6062\u590d \u00b7 ctrl+p \u547d\u4ee4\u9762\u677f \u00b7 / slash \u547d\u4ee4 \u00b7 ctrl+o \u5c55\u5f00\u63a8\u7406 \u00b7 shift+tab \u6a21\u5f0f\u5faa\u73af \u00b7 ctrl+q / /exit \u9000\u51fa",
    to: "Keys: ctrl+n new session \u00b7 ctrl+s resume \u00b7 ctrl+p command palette \u00b7 / slash commands \u00b7 ctrl+o expand reasoning \u00b7 shift+tab mode cycle \u00b7 ctrl+q / /exit quit",
  },

  {
    id: "session-list-snapshot-header",
    from: ".map((header) => {\n\t\tconst summary = toSummary(header);",
    to: ".map((entry) => {\n\t\tconst header = entry?.header ?? entry;\n\t\tconst summary = toSummary(header);",
  },

  // --- dsh 0.1.5 host-compat ---------------------------------------------
  // 0.1.5 dropped the durable `assistant/chunk` stream event (it commits one
  // `assistant/attempt` when an attempt settles and publishes in-flight deltas
  // as transient `agent/assistant-stream` frames). The TUI renders assistant
  // text only from chunks pushed into its StreamRenderer, so on 0.1.5 a turn
  // finished with nothing on screen — the live area stayed frozen on the
  // spinner. Two halves: consume the transient frames (restores live
  // streaming) and, when nothing streamed, commit the settled message text.
  {
    id: "compat-assistant-stream-subscribe",
    probe: "dsh-compat:agent-stream — 0.1.5 publishes in-flight deltas",
    from: '\t\tthis.streamFeed = this.ctx.on("session/event", (owner, event) => {\n\t\t\tif (owner.id !== id) return;\n\t\t\tif (this.replayActive) {\n\t\t\t\tthis.streamEventBacklog.push(event);\n\t\t\t\treturn;\n\t\t\t}\n\t\t\tthis.handleStreamEvent(event);\n\t\t});',
    to: '\t\tthis.streamFeed = this.ctx.on("session/event", (owner, event) => {\n\t\t\tif (owner.id !== id) return;\n\t\t\tif (this.replayActive) {\n\t\t\t\tthis.streamEventBacklog.push(event);\n\t\t\t\treturn;\n\t\t\t}\n\t\t\tthis.handleStreamEvent(event);\n\t\t});\n\t\t/* dsh-compat:agent-stream — 0.1.5 publishes in-flight deltas as transient `agent/assistant-stream` frames (global dispatch on the agent scope), not as durable `assistant/chunk` session events. Fold them into the same handler so live rendering keeps working. */\n\t\tthis.streamLiveFeed = this.ctx.on("agent/assistant-stream", ({ agent, frame }) => {\n\t\t\tif (agent.session.id !== id || this.replayActive) return;\n\t\t\tif (frame.type === "start") {\n\t\t\t\tthis.__dsh015Streamed = false;\n\t\t\t\tthis.__dsh015Turn = frame.turn;\n\t\t\t\tthis.__dsh015Step = frame.step;\n\t\t\t\treturn;\n\t\t\t}\n\t\t\tif (frame.type !== "chunk") return;\n\t\t\tthis.handleStreamEvent({\n\t\t\t\ttype: "assistant/chunk",\n\t\t\t\ttime: frame.time,\n\t\t\t\tdata: {\n\t\t\t\t\tturn: this.__dsh015Turn,\n\t\t\t\t\tstep: this.__dsh015Step,\n\t\t\t\t\tchunk: frame.chunk\n\t\t\t\t}\n\t\t\t});\n\t\t}, { global: true });',
  },
  {
    id: "compat-assistant-stream-field",
    probe: "dsh-compat:agent-stream — transient 0.1.5 live-stream subscription",
    from: "\t/** 流式提交供给的 session/event 订阅；随会话挂载/卸载。 */\n\tstreamFeed = null;",
    to: "\t/** 流式提交供给的 session/event 订阅；随会话挂载/卸载。 */\n\tstreamFeed = null;\n\t/** dsh-compat:agent-stream — transient 0.1.5 live-stream subscription; mounted/disposed with the session. */\n\tstreamLiveFeed = null;",
  },
  {
    id: "compat-assistant-stream-dispose",
    probe: "this.streamLiveFeed?.();",
    from: "\t\tthis.streamFeed?.();\n\t\tthis.streamFeed = null;",
    to: "\t\tthis.streamFeed?.();\n\t\tthis.streamFeed = null;\n\t\tthis.streamLiveFeed?.();\n\t\tthis.streamLiveFeed = null;",
  },
  {
    id: "compat-chunk-flag",
    probe: "__dsh015Streamed = true;",
    from: '\t\t\tcase "assistant/chunk": {\n\t\t\t\tconst { chunk } = event.data;',
    to: '\t\t\tcase "assistant/chunk": {\n\t\t\t\tthis.__dsh015Streamed = true;\n\t\t\t\tconst { chunk } = event.data;',
  },
  {
    id: "compat-settled-message-text",
    probe: "dsh-compat:settled-message — the durable message carries",
    from: '\t\t\tcase "assistant/message":\n\t\t\t\tthis.commitReasoningBlock();\n\t\t\t\tif (event.data.usage !== void 0) {',
    to: '\t\t\tcase "assistant/message":\n\t\t\t\t/* dsh-compat:settled-message — the durable message carries the authoritative content; without the 0.1.5 chunk stream nothing fed the renderer, so commit it here when no live frames arrived. */\n\t\t\t\tif (this.__dsh015Streamed !== true) {\n\t\t\t\t\tconst settled = event.data.message;\n\t\t\t\t\tif (settled !== void 0) {\n\t\t\t\t\t\tconst settledReasoning = foldReasoning(settled.content);\n\t\t\t\t\t\tif (settledReasoning !== "") {\n\t\t\t\t\t\t\tif (this.reasoningText === "") this.reasoningStartedAt = event.time;\n\t\t\t\t\t\t\tthis.reasoningText += settledReasoning;\n\t\t\t\t\t\t}\n\t\t\t\t\t\tconst settledText = foldText(settled.content);\n\t\t\t\t\t\tif (settledText !== "") this.streamRenderer.push(settledText);\n\t\t\t\t\t}\n\t\t\t\t}\n\t\t\t\tthis.__dsh015Streamed = false;\n\t\t\t\tthis.commitReasoningBlock();\n\t\t\t\tif (event.data.usage !== void 0) {',
  },
];
const fixesSha = crypto.createHash("sha256").update(JSON.stringify(FIXES)).digest("hex");

const pkgDir = path.resolve(path.dirname(bundlePath), "..");
const markerPath = path.join(pkgDir, ".dsh-tui-ru.json");
const origPath = `${bundlePath}.orig`;

let bundle;
try {
  bundle = fs.readFileSync(bundlePath, "utf8");
} catch (e) {
  log(`cannot read bundle: ${e.message}`);
  process.exit(1);
}
const bundleSha = crypto.createHash("sha256").update(bundle).digest("hex");

// Already patched with this exact map on this exact bundle?
let marker = null;
try {
  marker = JSON.parse(fs.readFileSync(markerPath, "utf8"));
} catch {}
if (marker && marker.mapSha === mapSha && marker.bundleSha === bundleSha
    && marker.fixesSha === fixesSha) {
  log(`up to date: ${bundlePath}`);
  process.exit(0);
}

// The TUI's own defaults first: they are code, not copy, and the translation
// map below must not be able to mask them.
const fixNotes = [];
for (const fix of FIXES) {
  // Insert-style fixes keep their anchor, so only their probe distinguishes an
  // applied bundle from a pristine one.
  if (fix.probe !== undefined && bundle.includes(fix.probe)) {
    fixNotes.push(`${fix.id}: already applied`);
    continue;
  }
  if (bundle.includes(fix.to) && !bundle.includes(fix.from)) {
    fixNotes.push(`${fix.id}: already applied`);
    continue;
  }
  if (!bundle.includes(fix.from)) {
    fixNotes.push(`${fix.id}: not present in this version (skipped)`);
    continue;
  }
  bundle = bundle.split(fix.from).join(fix.to);
  fixNotes.push(`${fix.id}: applied`);
}

// Apply replacements longest-first (so overlapping literals stay consistent).
const entries = Object.entries(map).sort((a, b) => b[0].length - a[0].length);
const missing = [];
let applied = 0;
for (const [k, v] of entries) {
  if (!bundle.includes(k)) {
    missing.push(k);
    continue;
  }
  bundle = bundle.split(k).join(v);
  applied++;
}

// Verification: no applied key may remain.
const leftovers = entries.filter(([k]) => bundle.includes(k)).map(([k]) => k);
if (leftovers.length) {
  log(`verification failed: ${leftovers.length} keys still present — bundle NOT modified`);
  for (const k of leftovers.slice(0, 5)) log(`  still present: ${JSON.stringify(k)}`);
  process.exit(1);
}

// First-time backup of the pristine bundle.
if (!fs.existsSync(origPath)) {
  fs.writeFileSync(origPath, fs.readFileSync(bundlePath));
  log(`backup written: ${origPath}`);
}

// Atomic write + marker.
const tmpPath = `${bundlePath}.ru-tmp`;
fs.writeFileSync(tmpPath, bundle);
fs.renameSync(tmpPath, bundlePath);
fs.writeFileSync(
  markerPath,
  `${JSON.stringify(
    {
      mapSha,
      fixesSha,
      bundleSha,
      at: new Date().toISOString(),
      stringsApplied: applied,
      fixes: fixNotes,
    },
    null,
    2
  )}\n`
);

log(`patched ${bundlePath}: ${applied} strings replaced, ${missing.length} not present in this version (covered by longer entries or plugin-version drift)`);
for (const note of fixNotes) log(`  fix ${note}`);
const leftoverCjk = remainingCjkLiterals(bundle);
if (leftoverCjk > 0) {
  log(`WARNING: ${leftoverCjk} Chinese string literals remain in ${bundlePath}`);
  log("  the translation map may be stale for this bundle version — extend i18n.json and re-run");
}
process.exit(0);
