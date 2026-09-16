/** Shared helpers for the .agent/scripts node tools (relative imports). */

export const NL = String.fromCharCode(10)
export const ENDPOINT = 'http://127.0.0.1:11434/api/chat'

// Parse `--key value` argv pairs. `defaults` seeds the result; `numeric` maps a
// flag name to a result key set only when the value is a positive number.
export function parseArgs(argv, defaults, numeric) {
  const out = defaults || {}
  for (let i = 0; i < argv.length; i += 2) {
    const key = argv[i]
    if (!key || !key.startsWith('--')) { i -= 1; continue }
    const name = key.slice(2)
    if (numeric && numeric[name]) {
      const value = Number(argv[i + 1])
      if (value > 0) out[numeric[name]] = value
    } else {
      out[name] = argv[i + 1]
    }
  }
  return out
}

// POST one non-streaming chat turn to the local Ollama endpoint.
// `opts.mentionModel` appends the model to a non-OK HTTP error; `opts.trim`
// trims the returned content. Both are opt-in so callers keep their wording.
export async function chat(model, system, user, temperature, opts) {
  const o = opts || {}
  const res = await fetch(ENDPOINT, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      model,
      stream: false,
      options: { temperature: Number(temperature) || 0.2 },
      messages: [
        { role: 'system', content: system },
        { role: 'user', content: user },
      ],
    }),
  })
  if (!res.ok) throw new Error('ollama HTTP ' + res.status + (o.mentionModel ? ' for ' + model : ''))
  const data = await res.json()
  const text = data && data.message ? String(data.message.content || '') : ''
  return o.trim ? text.trim() : text
}

// Run main() and report a thrown error as `NAME: <error>` + exit 1.
export function runMain(name, main) {
  main().catch(function (e) { console.error(name + ': ' + e); process.exit(1) })
}
