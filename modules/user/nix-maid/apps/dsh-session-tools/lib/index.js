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
    description: "переименовать текущую сессию (закрепить заголовок)",
    input: { hint: "<новое название>" },
    handler: async ({ rawInput, agent }) => {
      const title = rawInput.trim()
      if (title === "") {
        return { kind: "error", text: "usage: /rename <новое название>" }
      }
      const titles = ctx.get("sessionTitle")
      if (titles === undefined) {
        return { kind: "error", text: "переименование недоступно: нет session-title сервиса" }
      }
      try {
        const accepted = titles.rename(agent.session, title)
        return { kind: "success", text: `заголовок → «${accepted.title}»` }
      } catch (error) {
        return { kind: "error", text: error instanceof Error ? error.message : String(error) }
      }
    },
  })

  ctx.commands.register({
    name: "status",
    description: "сводка по текущей сессии: id, cwd, пресет, размер лога",
    handler: async ({ agent }) => {
      const session = agent?.session
      if (session === undefined || session === null) {
        return { kind: "error", text: "нет текущей сессии" }
      }
      const h = session.header ?? {}
      return {
        kind: "success",
        text: [
          `id: ${h.id ?? "?"}`,
          `cwd: ${h.cwd ?? "—"}`,
          `пресет: ${h.agentPreset ?? "—"}`,
          `родитель: ${h.parentSession ?? "—"}`,
          `событий: ${session.events?.length ?? "?"}`,
        ].join("\n"),
      }
    },
  })

  /** Write context for the memory service — the same shape the /memory command uses. */
  const memoryWrite = (invocation) => ({ agent: invocation?.agent })

  ctx.commands.register({
    name: "remember",
    description: "запомнить факт (алиас /memory add --track=user)",
    input: { hint: "<что запомнить>" },
    handler: async (invocation) => {
      const input = String(invocation?.rawInput ?? "").trim()
      if (input === "") {
        return { kind: "error", text: "usage: /remember <что запомнить>" }
      }
      const memory = ctx.get("memory")
      if (memory === undefined) {
        return { kind: "error", text: "memento недоступен" }
      }
      try {
        await memory.add(
          { track: "user", scope: "user-global", text: input, source: "command" },
          memoryWrite(invocation),
        )
        return { kind: "success", text: "запомнил." }
      } catch (error) {
        return { kind: "error", text: error instanceof Error ? error.message : String(error) }
      }
    },
  })

  ctx.commands.register({
    name: "forget",
    description: "удалить запись из памяти (алиас /memory remove)",
    input: { hint: "<уникальный фрагмент>" },
    handler: async (invocation) => {
      const match = String(invocation?.rawInput ?? "").trim()
      if (match === "") {
        return { kind: "error", text: "usage: /forget <уникальный фрагмент>" }
      }
      const memory = ctx.get("memory")
      if (memory === undefined) {
        return { kind: "error", text: "memento недоступен" }
      }
      try {
        await memory.remove(
          { track: "user", scope: "user-global", match },
          memoryWrite(invocation),
        )
        return { kind: "success", text: "удалил." }
      } catch (error) {
        return { kind: "error", text: error instanceof Error ? error.message : String(error) }
      }
    },
  })
}
