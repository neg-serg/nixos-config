pragma Singleton
import QtQuick
import Quickshell
import qs.Settings

// Widget visibility registry driven by Settings.panelLayout.
// Widgets remain statically defined in Bar.qml (they have complex per-instance
// properties/wrappers that prevent dynamic instantiation). This registry only
// resolves which widgets are visible.
//
// Dependencies read inside a function that lives in another QML document are not
// captured by the caller's binding, so this file must stay side-effect free: the
// consumers read Settings.settings.panelLayout themselves and pass the value to
// visibleSetFor(). That read happens in their own binding, which is what keeps
// the bar in sync with Settings.json (a cached property or a plain isVisible()
// helper silently pinned the bar to the default layout).
Singleton {
    id: root

    // Default layout used when Settings.panelLayout is absent/invalid
    readonly property var defaultLayout: ({
            left: ["clock", "workspaces", "keyboard", "network", "weather"],
            right: ["media", "mpdFlags", "sysmon", "pill", "systray", "microphone", "volume", "genelec"]
        })

    // Widget-id -> true lookup for a panelLayout value.
    // A widget listed in either section is visible; a section only decides which
    // row hosts it. Each ID appears at most once (first occurrence wins).
    function visibleSetFor(panelLayout) {
        var pl = (panelLayout && typeof panelLayout === 'object') ? panelLayout : defaultLayout;
        var left = _asList(pl.left, defaultLayout.left);
        var right = _asList(pl.right, defaultLayout.right);
        var seen = {};
        var all = left.concat(right);
        for (var i = 0; i < all.length; i++) {
            var id = String(all[i]);
            if (!seen[id])
                seen[id] = true;
        }
        return seen;
    }

    // JSON lists arrive from the settings adapter as Qt sequence wrappers
    // (V4Sequence), for which Array.isArray() is false; accept any array-like and
    // normalise it to a plain JS array of ids.
    function _asList(value, fallback) {
        if (value === undefined || value === null || typeof value === 'string')
            return fallback;
        var n = value.length;
        if (typeof n !== 'number' || n < 0)
            return fallback;
        var out = [];
        for (var i = 0; i < n; i++)
            out.push(String(value[i]));
        return out;
    }

    // Returns the sort index for a widget in a given section ("left" or "right").
    // Widgets not in the section get index 9999 (pushed to end / hidden).
    // Imperative helper only: it reads Settings directly and is not reactive.
    function orderIndex(widgetId, section) {
        var pl = Settings.settings ? Settings.settings.panelLayout : undefined;
        var list = (section === "left")
            ? ((pl && pl.left) ? pl.left : defaultLayout.left)
            : ((pl && pl.right) ? pl.right : defaultLayout.right);
        for (var i = 0; i < list.length; i++) {
            if (list[i] === widgetId)
                return i;
        }
        return 9999;
    }
}
