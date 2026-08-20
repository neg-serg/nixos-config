/**
 * dsh-boulder, browser half: countdown/status toast.
 *
 * Renders the 'Resuming in Ns... (K tasks remaining)' toast for the
 * todo-continuation enforcer. The host pushes messages via a best-effort
 * server->client call; the toast also works standalone: call
 * window.__boulderToast(message) from anywhere (e.g. devtools) to test.
 */

window.__ModuleLoader__.load({
  id: 'dsh-boulder',
  factory: (require) => {
    function renderToast(message) {
      let el = document.getElementById('dsh-boulder-toast')
      if (!el) {
        el = document.createElement('div')
        el.id = 'dsh-boulder-toast'
        el.style.cssText = 'position:fixed;bottom:16px;right:16px;z-index:9999;background:#b45309;color:#fff;padding:8px 12px;border-radius:8px;font-family:monospace;box-shadow:0 2px 8px rgba(0,0,0,0.35);white-space:pre'
        document.body.appendChild(el)
      }
      el.textContent = message
      if (window.__boulderToastTimer) clearTimeout(window.__boulderToastTimer)
      window.__boulderToastTimer = setTimeout(function () { el.remove() }, 900)
    }

    function apply(ctx) {
      // Expose the global so the host (or tests) can trigger the toast.
      window.__boulderToast = renderToast
      // Subscribe to host pushes if the connection service exposes an event bus.
      if (ctx && ctx.on && typeof ctx.on === 'function') {
        try {
          ctx.on('boulder-toast', function (payload) {
            if (payload && payload.message) renderToast(payload.message)
          })
        } catch (e) { /* no event bus in this context */ }
      }
    }

    // The toast needs no cordis services; the inject must stay EMPTY. The old
    // value (own package name) is not a service the client runtime provides,
    // so the entry stayed pending and the whole web boot failed.
    return { apply, inject: [] }
  },
});
