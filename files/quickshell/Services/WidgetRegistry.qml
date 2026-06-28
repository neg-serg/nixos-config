pragma Singleton
import QtQuick
import Quickshell
import qs.Settings

// Widget visibility and ordering registry driven by Settings.panelLayout.
// Widgets remain statically defined in Bar.qml (they have complex per-instance
// properties/wrappers that prevent dynamic instantiation). This registry
// controls which widgets are visible and provides sort keys for RowLayout ordering.
Singleton {
    id: root

    // Default layout used when Settings.panelLayout is absent/invalid
    readonly property var _defaultLayout: ({
        left: ["clock", "workspaces", "keyboard", "network", "weather"],
        right: ["media", "mpdFlags", "sysmon", "pills", "systray", "microphone", "volume"]
    })

    // Resolved layout: Settings override or default
    readonly property var layout: {
        var pl = Settings.settings ? Settings.settings.panelLayout : undefined;
        if (!pl || typeof pl !== 'object') return _defaultLayout;
        var left = (pl.left && Array.isArray(pl.left)) ? pl.left : _defaultLayout.left;
        var right = (pl.right && Array.isArray(pl.right)) ? pl.right : _defaultLayout.right;
        return { left: left, right: right };
    }

    // Set of all widget IDs present in the layout (for quick visibility check).
    // Each ID appears at most once (first occurrence wins).
    readonly property var _activeSet: {
        var seen = {};
        var all = (layout.left || []).concat(layout.right || []);
        for (var i = 0; i < all.length; i++) {
            var id = String(all[i]);
            if (!seen[id]) seen[id] = true;
        }
        return seen;
    }

    // Returns true if the widget should be visible in the bar
    function isVisible(widgetId) {
        return !!_activeSet[widgetId];
    }

    // Returns the sort index for a widget in a given section ("left" or "right").
    // Widgets not in the section get index 9999 (pushed to end / hidden).
    function orderIndex(widgetId, section) {
        var list = (section === "left") ? layout.left : layout.right;
        if (!list) return 9999;
        for (var i = 0; i < list.length; i++) {
            if (list[i] === widgetId) return i;
        }
        return 9999;
    }
}
