.pragma library

// ScreenUtil — null-safe screen access helpers.
//
// Direct use of the QML `Screen` attached property instantiates
// QQuickScreenAttached on the referencing object; when that object's window
// has no screen yet (startup, monitor churn, teardown) it crashes inside
// QWindow::screen() — the dominant quickshell crash signature on this host
// (~73% of reports). Use these helpers instead: they fall back to the item's
// window screen and then to the first QGuiApplication screen, never touching
// the attached property.

// A real screen, as opposed to something that merely pretends to be one: the
// guard used to ask for `virtualGeometry`, which no screen object in this stack
// has (QuickshellScreenInfo exposes x/y/width/height). The condition was
// therefore always false and every caller silently fell through to the next
// candidate — see isScreen() for what is actually checked.
function isScreen(candidate) {
    return !!(candidate && typeof candidate.width === "number" && typeof candidate.height === "number");
}

function screen(item) {
    if (item) {
        if (isScreen(item.screen)) return item.screen;
        var w = item.Window ? item.Window.window : null;
        if (w && isScreen(w.screen)) return w.screen;
    }
    var apps = Qt.application ? Qt.application.screens : null;
    if (apps && apps.length > 0 && isScreen(apps[0])) return apps[0];
    return null;
}

function dpr(item) {
    var s = screen(item);
    return s && s.devicePixelRatio ? s.devicePixelRatio : 1.0;
}

function width(item) {
    var s = screen(item);
    if (s) return s.width;
    return item && item.width ? item.width : 0;
}

function height(item) {
    var s = screen(item);
    if (s) return s.height;
    return item && item.height ? item.height : 0;
}

// The screen's rectangle in the global layout, or null when no screen could be
// resolved (the callers have their own fallbacks for that).
function geometry(item) {
    var s = screen(item);
    if (!s) return null;
    return Qt.rect(s.x || 0, s.y || 0, s.width, s.height);
}
