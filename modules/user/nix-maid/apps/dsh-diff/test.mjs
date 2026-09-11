#!/usr/bin/env node
/**
 * dsh-diff functional test.
 *
 * The risky logic is the patch reconstruction (the card's old/new texts are
 * derived from `git diff` rather than from reading files), so the parser gets
 * the bulk of the assertions. The rest drives the real tool definition through
 * its contract — execute → presentationMeta → presentResult — and the /diff
 * command against a fake subprocess.
 */
import { apply, inject, name, parsePatch } from "./lib/index.js";

let pass = 0;
let fail = 0;
const ok = (cond, label) => {
  if (cond) {
    pass += 1;
    console.log("  ✅ " + label);
  } else {
    fail += 1;
    console.log("  ❌ " + label);
  }
};

const PATCH = `diff --git a/src/app.js b/src/app.js
index 1111111..2222222 100644
--- a/src/app.js
+++ b/src/app.js
@@ -1,4 +1,4 @@
 const a = 1;
-const b = 2;
+const b = 3;
 export { a, b };
`;
const NEW_FILE = `diff --git a/new.txt b/new.txt
new file mode 100644
index 0000000..3333333
--- /dev/null
+++ b/new.txt
@@ -0,0 +1,2 @@
+one
+two
`;
const DELETED = `diff --git a/gone.txt b/gone.txt
deleted file mode 100644
index 4444444..0000000
--- a/gone.txt
+++ /dev/null
@@ -1,2 +0,0 @@
-bye
-now
`;
const BINARY = `diff --git a/logo.png b/logo.png
index 5555555..6666666 100644
Binary files a/logo.png and b/logo.png differ
`;
const SPACES = `diff --git "a/my file.txt" "b/my file.txt"
index 7777777..8888888 100644
--- "a/my file.txt"
+++ "b/my file.txt"
@@ -1 +1 @@
-old
+new
`;

// ── pure parser ──────────────────────────────────────────────────────────────
{
  const files = parsePatch(PATCH);
  ok(files.length === 1, "one file parsed from a simple patch");
  const f = files[0];
  ok(f.path === "src/app.js", "the changed path is taken from the b-side of the header");
  ok(f.added === 1 && f.removed === 1, "added/removed counts");
  ok(f.oldText === "const a = 1;\nconst b = 2;\nexport { a, b };", "oldText = context + removed lines");
  ok(f.newText === "const a = 1;\nconst b = 3;\nexport { a, b };", "newText = context + added lines");
  ok(f.binary === false, "a text patch is not flagged binary");
}
{
  const f = parsePatch(NEW_FILE)[0];
  ok(f.oldText === null, "a new file has oldText=null (the presenter's create contract)");
  ok(f.newText === "one\ntwo", "the new file's content");
}
{
  const f = parsePatch(DELETED)[0];
  ok(f.path === "gone.txt", "deleted file: path comes from the a-side");
  ok(f.newText === "", "a deleted file has an empty newText");
  ok(f.oldText === "bye\nnow", "a deleted file keeps its old content");
}
{
  const files = parsePatch(PATCH + NEW_FILE + BINARY);
  ok(files.length === 3, "multiple file blocks are split");
  ok(files.map((f) => f.path).join(",") === "src/app.js,new.txt,logo.png", "file order and paths");
  ok(files[2].binary === true, "binary patches are flagged");
  ok(files[2].added === 0 && files[2].removed === 0, "binary patches carry no line counts");
}
{
  const f = parsePatch(SPACES)[0];
  ok(f.path === "my file.txt", "quoted paths with spaces are unquoted");
}
{
  ok(parsePatch("").length === 0, "an empty patch yields no files");
  ok(parsePatch("not a diff at all\n").length === 0, "non-patch text yields no files");
}
{
  const noNewline = `diff --git a/x b/x
--- a/x
+++ b/x
@@ -1 +1 @@
-a
+b
\\ No newline at end of file
`;
  const f = parsePatch(noNewline)[0];
  ok(f.newText === "b", "the \\ No newline marker is not treated as content");
}
{
  // Every projection must satisfy the presenter's FileDiff contract.
  const all = parsePatch(PATCH + NEW_FILE + DELETED + BINARY);
  ok(
    all.every((f) => typeof f.path === "string" && (f.oldText === null || typeof f.oldText === "string") && typeof f.newText === "string"),
    "every parsed entry satisfies the FileDiff contract"
  );
}

// ── plugin wiring ────────────────────────────────────────────────────────────
ok(name === "dsh-diff", "plugin name matches the package/patch row");
ok(inject.includes("tools") && inject.includes("commands") && inject.includes("subprocess"), "injects tools + commands + subprocess");

function harness({ diffPatch = PATCH, diffCode = 0, stderr = "", statusOut = "?? scratch.txt\n" } = {}) {
  const spawns = [];
  let tool;
  let command;
  const ctx = {
    tools: { register: (def) => { tool = def; } },
    commands: { register: (def) => { command = def; } },
    subprocess: {
      resolveExecutable: async () => "/nix/store/fake-git",
      spawn: (spec) => {
        spawns.push(spec);
        const isStatus = spec.argv.includes("status");
        const out = isStatus ? statusOut : diffPatch;
        return {
          done: Promise.resolve({ exitCode: isStatus ? 0 : diffCode, signal: null }),
          collected: {
            stdout: { readFrom: () => ({ text: out, nextOffset: out.length, lossy: false }) },
            stderr: { readFrom: () => ({ text: isStatus ? "" : stderr, nextOffset: stderr.length, lossy: false }) },
          },
        };
      },
    },
  };
  apply(ctx);
  return { tool, command, spawns };
}

const exec = { agent: { session: { header: { cwd: "/repo" } } }, signal: undefined };

{
  const { tool, command } = harness();
  ok(tool?.name === "show_diff", "registers the show_diff tool");
  ok(typeof tool.execute === "function", "the tool has execute");
  ok(typeof tool.output.render === "function" && typeof tool.output.presentationMeta === "function", "the tool declares output { render, presentationMeta }");
  ok(command?.name === "diff", "registers the /diff command");
}

// ── tool: execute → meta → presenter ─────────────────────────────────────────
{
  const { tool, spawns } = harness();
  const value = await tool.execute({}, exec);
  ok(spawns[0].argv.join(" ").includes("diff HEAD --no-color --no-ext-diff"), "defaults to the working tree (git diff HEAD)");
  ok(spawns[0].cwd === "/repo", "runs in the session cwd");
  ok(value.summary.includes("1 file(s)") && value.summary.includes("+1 −1"), "the summary carries totals");
  ok(value.files[0].path === "src/app.js", "the canonical value lists the files");
  ok(value.untracked.includes("scratch.txt"), "untracked files are reported separately");

  const meta = tool.output.presentationMeta({}, value);
  ok(Array.isArray(meta.diffs) && meta.diffs.length === 1, "presentationMeta projects diffs");
  ok(meta.diffs[0].oldText === "const a = 1;\nconst b = 2;\nexport { a, b };", "the projected diff carries oldText");
  ok(
    meta.diffs[0].oldText !== null && typeof meta.diffs[0].newText === "string",
    "the projected diff satisfies FileDiff"
  );

  const view = tool.presentResult({}, { meta });
  ok(view.card === "diff", "presentResult declares the structured diff card");
  ok(view.diffs.length === 1, "the card carries the diffs");
  ok(tool.output.render({}, value)[0].type === "text", "render produces model-facing text");

  ok(tool.presentResult({}, { meta: { diffs: [] } }) === undefined, "an empty diff produces no card");
  ok(tool.presentResult({}, {}) === undefined, "missing metadata produces no card");
}
{
  const { tool, spawns } = harness();
  await tool.execute({ staged: true }, exec);
  ok(spawns[0].argv.join(" ").includes("diff --cached"), "--staged reviews the index");
  ok(spawns.length === 1, "--staged does not ask for untracked files");
}
{
  const { tool, spawns } = harness();
  await tool.execute({ ref: "origin/main" }, exec);
  ok(spawns[0].argv.join(" ").includes("diff origin/main"), "--ref compares against a ref");
}
{
  const { tool } = harness();
  const value = await tool.execute({ path: "src" }, exec);
  ok(value.summary.includes("1 file(s)"), "a path argument still returns the review");
}
{
  const { tool } = harness({ diffPatch: "", statusOut: "" });
  const value = await tool.execute({}, exec);
  ok(value.summary.includes("no uncommitted changes"), "an empty working tree is reported clearly");
  ok(tool.output.presentationMeta({}, value).diffs.length === 0, "an empty patch projects no diffs");
}
{
  const { tool } = harness({ diffCode: 128, stderr: "fatal: not a git repository" });
  let threw = "";
  try {
    await tool.execute({}, exec);
  } catch (error) {
    threw = String(error.message);
  }
  ok(threw.includes("not a git repository"), "a git failure surfaces git's own message");
}

// ── command ──────────────────────────────────────────────────────────────────
{
  const { command, spawns } = harness();
  const r = await command.handler({ rawInput: "", agent: exec.agent });
  ok(r.kind === "success", "/diff succeeds");
  ok(r.text.includes("src/app.js"), "the file list reaches the reply");
  ok(!r.text.includes("@@"), "the patch stays out of the default view");
  ok(r.text.includes("--patch"), "the reply points at the full patch");
  ok(spawns[0].argv.join(" ").includes("diff HEAD"), "the command shares the tool's git invocation");
}
{
  const { command } = harness();
  const r = await command.handler({ rawInput: "--patch", agent: exec.agent });
  ok(r.kind === "success" && r.text.includes("@@ -1,4 +1,4 @@"), "--patch includes the unified diff");
}
{
  const { command, spawns } = harness();
  await command.handler({ rawInput: "src/app.js --staged", agent: exec.agent });
  const argv = spawns[0].argv.join(" ");
  ok(argv.includes("diff --cached") && argv.endsWith("-- src/app.js"), "a path plus --staged is forwarded to git");
}
{
  const { command } = harness();
  const r = await command.handler({ rawInput: "--nope", agent: exec.agent });
  ok(r.kind === "error" && r.text.includes("--nope"), "an unknown flag is rejected");
}
{
  const { command } = harness();
  const r = await command.handler({ rawInput: "--ref", agent: exec.agent });
  ok(r.kind === "error" && r.text.includes("usage"), "--ref without a value returns the usage");
}
{
  const { command } = harness({ diffCode: 1, stderr: "boom" });
  const r = await command.handler({ rawInput: "", agent: exec.agent });
  ok(r.kind === "error" && r.text.includes("boom"), "a git failure becomes a command error");
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
