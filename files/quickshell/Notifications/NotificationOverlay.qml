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

    implicitWidth: 520
    implicitHeight: 600

    NotificationDisplay {
        id: display
        anchors.fill: parent
    }
    mask: Region { item: display }
    Component.onCompleted: {
        console.log("[Overlay] loaded, connecting");
        NotificationManager.notif.connect(display.addNotification);
        NotificationManager.showAll.connect(display.addSet);
        NotificationManager.dismissAll.connect(display.dismissAll);
        NotificationManager.discardAll.connect(display.discardAll);
        console.log("[Overlay] connected, window visible:", root.visible);
    }
}
