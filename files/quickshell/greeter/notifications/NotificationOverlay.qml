pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
	id: root
	WlrLayershell.namespace: "shell:notifications"
	exclusionMode: ExclusionMode.Ignore
	color: "transparent"

	anchors {
		left: true
		top: true
		bottom: true
		right: true
	}

	property Component notifComponent: DaemonNotification {}

	NotificationDisplay {
		id: display
		anchors.fill: root

		stack.y: 5 + 55
		stack.x: 72
	}

	visible: display.stack.children.length !== 0

	mask: Region { item: display.stack }
	HyprlandWindow.visibleMask: Region {
		id: visibleMaskRegion
		regions: display.stack.children.map(child => child.mask)
	}

	Component.onCompleted: {
		NotificationManager.overlay = root;
		NotificationManager.notif.connect(display.addNotification);
		NotificationManager.showAll.connect(display.addSet);
		NotificationManager.dismissAll.connect(display.dismissAll);
		NotificationManager.discardAll.connect(display.discardAll);
	}
}
