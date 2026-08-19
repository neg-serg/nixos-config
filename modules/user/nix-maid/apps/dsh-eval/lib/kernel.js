// Persistent JS kernel for dsh-eval, using node:vm so top-level let/const/var
// persist between calls in the same context. Line-delimited JSON protocol.
import { createContext, runInContext } from 'node:vm'
import { createInterface } from 'node:readline'

const rl = createInterface({ input: process.stdin })
let currentLogs = []
const consoleProxy = {
  log: (...a) => currentLogs.push(a.map(String).join(' ')),
  error: (...a) => currentLogs.push(a.map(String).join(' ')),
}
let ctx = createContext({ console: consoleProxy })

function respond(rid, ok, stdout, error) {
  process.stdout.write(JSON.stringify({ id: rid, ok: ok, stdout: stdout, error: error || null }) + '\n')
}

rl.on('line', (line) => {
  line = line.trim()
  if (!line) return
  let req
  try { req = JSON.parse(line) } catch (e) { return }
  if (req.reset) {
    currentLogs = []
    ctx = createContext({ console: consoleProxy })
    respond(req.id, true, '', null)
    return
  }
  currentLogs = []
  let err = null
  try {
    runInContext(String(req.code || ''), ctx, { filename: '<eval>' })
  } catch (e) {
    err = String((e && e.stack) || e)
  }
  respond(req.id, err === null, currentLogs.join('\n'), err)
})
