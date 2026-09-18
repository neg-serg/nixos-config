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
