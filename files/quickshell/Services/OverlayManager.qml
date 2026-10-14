pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Tracks the single active overlay. When a new overlay opens,
// the previous one is dismissed — preventing multiple overlays
// from appearing simultaneously.
//
// Keyboard dismissal: touch ~/.cache/quickshell/dismiss-overlay
// (e.g. via hyprland bind: bind $mod+k exec touch ~/.cache/quickshell/dismiss-overlay)
Item {
    id: root

    property var activeOverlay: null

    // Trigger file for external (hyprland keybind) dismissal
    readonly property string _triggerPath: {
        var home = Quickshell.env("HOME") || "/tmp";
        return home + "/.cache/quickshell/dismiss-overlay";
    }

    Component.onCompleted: {
        // Ensure trigger file & dir exist so FileView can watch it
        var dir = root._triggerPath.replace(/\/[^/]+$/, "");
        Quickshell.execDetached(["mkdir", "-p", dir]);
        Quickshell.execDetached(["touch", root._triggerPath]);
    }

    FileView {
        id: dismissTrigger
        path: root._triggerPath
        watchChanges: true
        property bool _reloadPending: false
        onFileChanged: {
            if (dismissTrigger._reloadPending) return;
            dismissTrigger._reloadPending = true;
            Qt.callLater(function() {
                dismissTrigger._reloadPending = false;
                root.dismissActive();
                dismissTrigger.reload(); // reset watch for next trigger
            });
        }
        onLoadFailed: { /* file may not exist yet — fine */ }
    }

    function registerOverlay(overlay) {
        if (!overlay) return;
        if (root.activeOverlay && root.activeOverlay !== overlay) {
            try { root.activeOverlay.dismiss() } catch (e) {}
        }
        root.activeOverlay = overlay;
    }

    function unregisterOverlay(overlay) {
        if (root.activeOverlay === overlay) {
            root.activeOverlay = null;
        }
    }

    // Named overlays: the capsules register under a stable name ("calendar",
    // "weather") so IPC handlers and keybinds can toggle a panel without a
    // reference to its instance. The var is reassigned on every change so QML
    // sees the property update.
    property var namedOverlays: ({})

    function registerNamed(name, overlay) {
        if (!name || !overlay) return;
        var next = {};
        for (var k in root.namedOverlays) next[k] = root.namedOverlays[k];
        next[name] = overlay;
        root.namedOverlays = next;
    }

    function unregisterNamed(name, overlay) {
        if (!name || root.namedOverlays[name] !== overlay) return;
        var next = {};
        for (var k in root.namedOverlays) {
            if (k !== name) next[k] = root.namedOverlays[k];
        }
        root.namedOverlays = next;
    }

    // Returns false when no capsule registered under that name (e.g. the module
    // is not in the bar layout), true once the toggle was handed over.
    function toggleNamed(name) {
        var overlay = root.namedOverlays[name];
        if (!overlay) return false;
        try { overlay.toggle(); } catch (e) { return false; }
        return true;
    }

    function dismissActive() {
        if (root.activeOverlay) {
            try { root.activeOverlay.dismiss() } catch (e) {}
            root.activeOverlay = null;
        }
    }
}
