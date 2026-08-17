/**
 * dsh-osm rate limiting.
 *
 * The public OSM APIs (Nominatim, Overpass, OSRM demo) are free but
 * community-funded and strictly rate-limited. This module gives every host a
 * serialized, minimum-interval gate so the harness's parallel tool scheduler
 * (maxParallelToolCalls can be high) cannot accidentally flood them. One
 * gate per host; concurrent callers queue in FIFO order and each waits until
 * `minIntervalMs` has passed since the previous call on the same host.
 */

export function createRateLimiter({ minIntervalMs = 1100 } = {}) {
  let tail = Promise.resolve()
  let lastAt = 0

  /**
   * Wait for this caller's turn on the host. Resolves when the call may go
   * out; the caller must perform the actual request itself.
   */
  function acquire() {
    const run = tail.then(async () => {
      const now = Date.now()
      const wait = lastAt + minIntervalMs - now
      if (wait > 0) {
        await new Promise((resolve) => setTimeout(resolve, wait))
      }
      lastAt = Date.now()
    })
    // Keep the chain alive even if a queued step rejects; each caller only
    // awaits its own `run`.
    tail = run.catch(() => {})
    return run
  }

  return { acquire }
}
