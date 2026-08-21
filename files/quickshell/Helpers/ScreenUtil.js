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

function screen(item) {
    if (item) {
        if (item.screen && item.screen.virtualGeometry) return item.screen;
        var w = item.Window ? item.Window.window : null;
        if (w && w.screen && w.screen.virtualGeometry) return w.screen;
    }
    var apps = Qt.application ? Qt.application.screens : null;
    if (apps && apps.length > 0 && apps[0]) return apps[0];
    return null;
}

function dpr(item) {
    var s = screen(item);
    return s && s.devicePixelRatio ? s.devicePixelRatio : 1.0;
}

function width(item) {
    var s = screen(item);
    if (s && s.virtualGeometry) return s.virtualGeometry.width;
    return item && item.width ? item.width : 0;
}

function height(item) {
    var s = screen(item);
    if (s && s.virtualGeometry) return s.virtualGeometry.height;
    return item && item.height ? item.height : 0;
}

function virtualGeometry(item) {
    var s = screen(item);
    return s && s.virtualGeometry ? s.virtualGeometry : null;
}
