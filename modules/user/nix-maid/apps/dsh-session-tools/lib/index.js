/**
 * dsh-session-tools: user-facing session conveniences for the dsh web GUI —
 * /rename (pin the session title), /status (id/cwd/preset/log size),
 * /remember and /forget (aliases for the memento memory service).
 *
 * Server-only plugin (no browser half): commands surface in the chat input
 * once registered on the host 'commands' service. The memory service
 * (ctx.memory) and title service (ctx.sessionTitle) are resolved lazily so
 * the plugin still boots when memento/session-title are absent.
 */

/** Cordis plugin name — must match the patch row / package name. */
export const name = "dsh-session-tools"

/** Required service: slash-command registry. */
export const inject = ["commands"]

export function apply(ctx) {
  ctx.commands.register({
    name: "rename",
    description: "rename the current session (pin its title)",
    input: { hint: "<new title>" },
    handler: async ({ rawInput, agent }) => {
      const title = rawInput.trim()
      if (title === "") {
        return { kind: "error", text: "usage: /rename <new title>" }
      }
      const titles = ctx.get("sessionTitle")
      if (titles === undefined) {
        return { kind: "error", text: "renaming unavailable: no session-title service" }
      }
      try {
        const accepted = titles.rename(agent.session, title)
        return { kind: "success", text: `title → «${accepted.title}»` }
      } catch (error) {
        return { kind: "error", text: error instanceof Error ? error.message : String(error) }
      }
    },
  })

  ctx.commands.register({
    name: "status",
    description: "current session summary: id, cwd, preset, log size",
    handler: async ({ agent }) => {
      const session = agent?.session
      if (session === undefined || session === null) {
        return { kind: "error", text: "no active session" }
      }
      const h = session.header ?? {}
      return {
        kind: "success",
        text: [
          `id: ${h.id ?? "?"}`,
          `cwd: ${h.cwd ?? "—"}`,
          `preset: ${h.agentPreset ?? "—"}`,
          `parent: ${h.parentSession ?? "—"}`,
          `events: ${typeof session.seq === 'number' ? session.seq : "?"}`,
        ].join("\n"),
      }
    },
  })

  /** Write context for the memory service — the same shape the /memory command uses. */
  const memoryWrite = (invocation) => ({ agent: invocation?.agent })

  ctx.commands.register({
    name: "remember",
    description: "remember a fact (alias of /memory add --track=user)",
    input: { hint: "<what to remember>" },
    handler: async (invocation) => {
      const input = String(invocation?.rawInput ?? "").trim()
      if (input === "") {
        return { kind: "error", text: "usage: /remember <what to remember>" }
      }
      const memory = ctx.get("memory")
      if (memory === undefined) {
        return { kind: "error", text: "memento is unavailable" }
      }
      try {
        await memory.add(
          { track: "user", scope: "user-global", text: input, source: "command" },
          memoryWrite(invocation),
        )
        return { kind: "success", text: "remembered." }
      } catch (error) {
        return { kind: "error", text: error instanceof Error ? error.message : String(error) }
      }
    },
  })

  ctx.commands.register({
    name: "forget",
    description: "delete a memory entry (alias of /memory remove)",
    input: { hint: "<unique fragment>" },
    handler: async (invocation) => {
      const match = String(invocation?.rawInput ?? "").trim()
      if (match === "") {
        return { kind: "error", text: "usage: /forget <unique fragment>" }
      }
      const memory = ctx.get("memory")
      if (memory === undefined) {
        return { kind: "error", text: "memento is unavailable" }
      }
      try {
        await memory.remove(
          { track: "user", scope: "user-global", match },
          memoryWrite(invocation),
        )
        return { kind: "success", text: "deleted." }
      } catch (error) {
        return { kind: "error", text: error instanceof Error ? error.message : String(error) }
      }
    },
  })
}
