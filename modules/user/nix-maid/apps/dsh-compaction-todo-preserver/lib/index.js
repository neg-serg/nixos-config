/**
 * dsh-compaction-todo-preserver: keep the todo list alive across session
 * compaction. dsh-tool-todo stores the list as "todo/write" session events
 * (last-write-wins projection); compaction collapses the log, so the model
 * can lose track of pending work. On compaction/end we re-append the
 * snapshot taken at compaction/start.
 *
 * Design: /etc/nixos/docs/howto/designs/rules-hooks.ru.md section 2.
 * Mounted via the profile's cordis.patch.yml insert row, same as dsh-osm.
 */

export const name = 'dsh-compaction-todo-preserver'

const latest = new Map() // sessionID -> todos[] (most recent todo/write)
const snapshot = new Map() // sessionID -> todos[] captured at compaction/start

export function apply(ctx) {
  ctx.on('session/event', (session, event) => {
    if (event.type === 'todo/write') {
      latest.set(session.id, event.data.todos)
      return
    }
    if (event.type === 'compaction/start') {
      const todos = latest.get(session.id)
      if (todos && todos.length > 0) snapshot.set(session.id, todos)
      return
    }
    if (event.type === 'compaction/end') {
      const todos = snapshot.get(session.id)
      snapshot.delete(session.id)
      if (todos && todos.length > 0) {
        // Re-append so the projection still shows the live list. A duplicate
        // in the log is harmless: the projection takes the last todo/write.
        session.append('todo/write', { todos })
      }
      return
    }
    if (event.type === 'session/end-seed') {
      latest.delete(session.id)
      snapshot.delete(session.id)
    }
  })
}
