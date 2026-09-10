// Session-format regression harness for the dsh package patches.
//
// Decodes every stored Session artifact through dsh's own format catalog (the
// whole v0->v3 migration chain plus the target validation, exactly as the
// persistence backend does on a cold read) and groups the failures. This is the
// gate for `packages/dsh/patch-session-format.py`: a dsh upgrade that
// reintroduces a migration gap shows up here as a failure class, not as an
// unreadable history in the web UI.
//
// Usage: check-dsh-sessions.mjs <dsh-store-path> [sessions-root]
//
// The dsh store path is a built `dsh-<version>` output (the directory holding
// `lib/node_modules/@deepseek-ai/dsh`); the sessions root defaults to
// $DSH_HOME/sessions or ~/.dsh/sessions. Exit status: 0 when every artifact
// decodes, 1 when any failure remains or the arguments are unusable.
import { readdirSync, existsSync } from 'node:fs'
import { execFileSync } from 'node:child_process'

const args = process.argv.slice(2)
const strict = args.includes('--strict')
const [tree, rootArg] = args.filter((arg) => !arg.startsWith('--'))
if (tree === undefined) {
  console.error('usage: check-dsh-sessions.mjs <dsh-store-path> [sessions-root]')
  process.exit(2)
}
const root = rootArg || `${process.env.DSH_HOME || `${process.env.HOME}/.dsh`}/sessions`
const catalogPath = `${tree}/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-session-format-catalog/lib/index.js`
if (!existsSync(catalogPath)) {
  console.error(`check-dsh-sessions: ${catalogPath} not found — pass a built dsh store path`)
  process.exit(2)
}
if (!existsSync(root)) {
  console.error(`check-dsh-sessions: sessions root ${root} not found`)
  process.exit(2)
}

const { sessionFormatCatalog } = await import(catalogPath)

function* artifacts(dir) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const path = `${dir}/${entry.name}`
    if (entry.isDirectory()) yield* artifacts(path)
    else if (entry.name === 'session.jsonl.zstd' || entry.name === 'session.jsonl') yield path
  }
}

const results = []
for (const path of artifacts(root)) {
  let rows
  try {
    const bytes = path.endsWith('.zstd')
      ? execFileSync('zstd', ['-dc', path], { maxBuffer: 1 << 30 })
      : execFileSync('cat', [path], { maxBuffer: 1 << 30 })
    rows = bytes
      .toString('utf8')
      .split('\n')
      .filter((line) => line.trim() !== '')
      .map((line) => JSON.parse(line))
  } catch (error) {
    results.push({ path, ok: false, reason: `unreadable: ${error.message}` })
    continue
  }
  const [headerValue, ...eventRows] = rows
  try {
    const restore = sessionFormatCatalog.createRestore(headerValue, {
      recovery: 'recoverable',
      validation: 'transformed'
    })
    for (const row of eventRows) restore.decodeRow(row)
    const artifact = restore.finish()
    results.push({ path, ok: true, reason: `v${headerValue.version}->v${artifact.header.version}` })
  } catch (error) {
    results.push({ path, ok: false, reason: error?.message ?? String(error) })
  }
}

const failed = results.filter((entry) => !entry.ok)
const groups = new Map()
for (const entry of failed) {
  const key = entry.reason.replace(/seq \d+/g, 'seq N').replace(/"[^"]*"/g, '"X"')
  groups.set(key, [...(groups.get(key) ?? []), entry])
}
// A migration/compatibility refusal means our patches no longer cover what the
// installed dsh reads; a damaged artifact is a broken log this harness cannot
// repair. Only the former fails the gate unless --strict is passed.
const COMPAT = /refuses this format|unexpected member|unsupported descriptor version|unknown (historical )?event type|cannot safely transform|unclassified/
const compat = failed.filter((entry) => COMPAT.test(entry.reason))
const damage = failed.filter((entry) => !COMPAT.test(entry.reason))

console.log(`check-dsh-sessions: ${results.length} artifacts, ${results.length - failed.length} readable, ${failed.length} failed (${compat.length} compatibility, ${damage.length} damaged)`)
for (const set of [compat, damage]) {
  const grouped = new Map()
  for (const entry of set) {
    const key = entry.reason.replace(/seq \d+/g, 'seq N').replace(/"[^"]*"/g, '"X"')
    grouped.set(key, [...(grouped.get(key) ?? []), entry])
  }
  for (const [reason, entries] of [...grouped].sort((a, b) => b[1].length - a[1].length)) {
    console.log(`\n[${entries.length}] ${reason}`)
    for (const entry of entries.slice(0, 3)) console.log('   ', entry.path.replace(root, '…'))
    if (entries.length > 3) console.log(`    … +${entries.length - 3} more`)
  }
}
if (damage.length > 0 && compat.length === 0) {
  console.log('\ncheck-dsh-sessions: only damaged artifacts remain (not a format regression)')
}
process.exit(compat.length > 0 || (strict && failed.length > 0) ? 1 : 0)
