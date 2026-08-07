pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// NotificationOverlay — live toast popups, dunst-style bottom-right.
// PanelWindow with ExclusionMode.Ignore so it doesn't displace other surfaces.
// Anchored bottom-right with dunst's 54px bottom offset.

PanelWindow {
    id: root
    WlrLayershell.namespace: "shell:notifications"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    color: "transparent"

    anchors {
        right: true
        bottom: true
    }

    WlrLayershell.margins {
        right: 12
        bottom: 54
    }

    implicitWidth: 620
    implicitHeight: 800

    NotificationDisplay {
        id: display
        anchors.fill: parent
    }
    // Only map the window while there are notifications to show; an always-on
    // transparent overlay at the topmost layer eats clicks over its whole area
    // even when empty (2026-08-07: clicks stopped reaching windows).
    visible: display.contentMaskHeight > 0
    // Restrict input to the actual card stack (bottom strip), not the full
    // 620x800 window. Region coords are window-local.
    mask: Region {
        width: 620
        height: display.contentMaskHeight
        y: 800 - display.contentMaskHeight
    }
    Component.onCompleted: {
        NotificationManager.notif.connect(display.addNotification);
        NotificationManager.showAll.connect(display.addSet);
        NotificationManager.dismissAll.connect(display.dismissAll);
        NotificationManager.discardAll.connect(display.discardAll);
    }
}
