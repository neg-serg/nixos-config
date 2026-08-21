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

    function dismissActive() {
        if (root.activeOverlay) {
            try { root.activeOverlay.dismiss() } catch (e) {}
            root.activeOverlay = null;
        }
    }
}
