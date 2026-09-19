// BarLayout — the numerical side of the bar's look, as plain functions.
//
// These used to live as methods of Bar.qml's root scope and were called through
// `rootScope.*` from deep inside the panel tree. They are pure — numbers in,
// numbers out — so they belong in a module: testable on their own, and the file
// that builds the bar stops being where the arithmetic lives.
//
// Environment overrides are read here too, in one place: they are perf-triage
// toggles that used to be spelled out as separate `Quickshell.env(...)` bindings
// in the scope.

.pragma library

// Width of the clipped wedge between the bar face and the panel, normalised to
// the face width. `QS_WEDGE_WIDTH_PCT` overrides the computed value.
function wedgeWidthNorm(faceWidth, seamWidth, env) {
    const ww = Number((env && env("QS_WEDGE_WIDTH_PCT")) || "");
    if (isFinite(ww) && ww > 0) return clamp01(ww / 100.0);
    const faceW = Math.max(1, faceWidth);
    const targetPx = Math.max(1, Math.round(seamWidth));
    const capPx = Math.round(faceW * 0.35);
    const wpx = Math.min(targetPx, capPx);
    return Math.max(0.02, Math.min(0.98, wpx / faceW));
}

// Alpha scale applied to the panel background. The setting is optional and can be
// anything, so a non-number falls back to the default.
function panelBgAlphaScale(settings, fallback) {
    const raw = settings ? settings.panelBgAlphaScale : undefined;
    let val = Number(raw);
    if (!isFinite(val)) val = fallback;
    return clamp01(val);
}

function clamp01(value) {
    const v = Number(value);
    if (!isFinite(v)) return 0;
    return Math.max(0, Math.min(1, v));
}

// `QS_DISABLE_WEDGE=1` / `QS_DISABLE_TRIANGLES=1` hard-disable the expensive
// paths (clipped wedges, triangle overlays) during perf triage.
function wedgeClipAllowed(env) {
    return ((env && env("QS_DISABLE_WEDGE")) || "") !== "1";
}

function trianglesAllowed(env) {
    return ((env && env("QS_DISABLE_TRIANGLES")) || "") !== "1";
}

// ── Startup gate (the "clean login" bar) ────────────────────────────────────
// The gate narrows the bar down to a couple of widgets until the first real
// window appears at login (see Bar/Bar.qml). Everything below is pure so the
// decisions can be reasoned about — and tested — away from the panel tree.

// Narrow a widget-visibility set down to `keepIds`. `keepIds` being null (or not
// array-like) means "no narrowing": the gate is open and the set passes through.
// Only ids that are visible anyway survive, so a kept widget still obeys
// Settings.panelLayout (and the extra conditions in Bar.qml, e.g. showWeatherInBar).
// Every id the input set knows about stays a boolean in the result: the panel reads
// them as `visible: panelWidgets["x"]`, and a dropped key would assign undefined to
// a bool property ("Unable to assign [undefined] to bool" in the log) instead of
// just hiding the widget.
function startupKeepSet(visibleSet, keepIds) {
    const visible = (visibleSet && typeof visibleSet === 'object') ? visibleSet : {};
    if (!keepIds || typeof keepIds.length !== 'number') return visible;
    const keep = {};
    for (let i = 0; i < keepIds.length; i++) keep[String(keepIds[i])] = true;
    const out = {};
    const ids = Object.keys(visible);
    for (let i = 0; i < ids.length; i++) out[ids[i]] = keep[ids[i]] === true;
    return out;
}

// JSON lists arrive from the settings adapter as Qt sequence wrappers
// (V4Sequence), for which Array.isArray() is false; accept any array-like,
// normalise it to strings and fall back when nothing usable is left.
function stringList(value, fallback) {
    const fb = (fallback && typeof fallback.length === 'number') ? fallback.slice() : [];
    if (value === undefined || value === null || typeof value === 'string') return fb;
    const n = value.length;
    if (typeof n !== 'number' || n < 0) return fb;
    const out = [];
    for (let i = 0; i < n; i++) out.push(String(value[i]));
    return out.length > 0 ? out : fb;
}

// Optional numeric setting: anything that is not a positive finite number falls
// back to the shipped default.
function positiveNumber(value, fallback) {
    const n = Number(value);
    return (isFinite(n) && n > 0) ? n : fallback;
}

// "Is this the first window?" — `clients` is the array straight out of
// `hyprctl -j clients`.
//
// Two kinds of clients do not mean "the desktop is in use" and are skipped:
// - hidden ones — daemons that keep an invisible window around (`nicotine -s`),
//   marked `hidden: true`;
// - windows on special workspaces (`ignoreSpecial`) — the scratchpads are
//   pre-launched at login, so they would end the clean look on their own.
//   Special workspaces carry negative ids and names prefixed `special:`;
//   windows on ordinary but unfocused workspaces still count.
function hasRealWindow(clients, ignoreSpecial) {
    if (!clients || typeof clients.length !== 'number') return false;
    for (let i = 0; i < clients.length; i++) {
        const c = clients[i];
        if (!c || c.mapped === false || c.hidden === true) continue;
        if (ignoreSpecial) {
            const ws = c.workspace || {};
            const name = (ws.name === undefined || ws.name === null) ? '' : String(ws.name);
            const id = Number(ws.id);
            if (name.indexOf('special:') === 0) continue;
            if (isFinite(id) && id < 0) continue;
        }
        return true;
    }
    return false;
}

// Freshness test for the login marker file, `mtimeSeconds` being `stat -c %Y`
// output and `windowMs` the accepted age. A missing or unreadable marker comes
// through as NaN and is never fresh, which keeps the gate down rather than
// guessing — a bar that thins itself out mid-session is worse than one that
// misses a pretty login.
function isFreshTimestamp(mtimeSeconds, nowSeconds, windowMs) {
    const mtime = Number(mtimeSeconds);
    const now = Number(nowSeconds);
    const window = Number(windowMs) / 1000;
    if (!isFinite(mtime) || !isFinite(now) || !(window > 0)) return false;
    const age = now - mtime;
    // A marker timestamped slightly in the future is a clock step, not a reason
    // to drop the gate.
    return age >= -60 && age <= window;
}
