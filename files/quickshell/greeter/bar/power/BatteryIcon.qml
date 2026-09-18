import QtQuick
import Quickshell.Services.UPower
import qs

Item {
	id: root
	required property UPowerDevice device;
	// Renamed from `scale`: that shadowed Item.scale (the property that actually
	// transforms the item) while being used as this icon's own multiplier.
	property real iconScale: 1;

	readonly property bool isCharging: root.device.state == UPowerDeviceState.Charging;
	readonly property bool isPluggedIn: isCharging || root.device.state == UPowerDeviceState.PendingCharge;
	readonly property bool isLow: root.device.percentage <= 0.20;

	width: 35 * root.iconScale
	height: 35 * root.iconScale

	Rectangle {
		anchors {
			horizontalCenter: parent.horizontalCenter
			bottom: parent.bottom
			bottomMargin: 4 * root.iconScale
		}

		width: 13 * root.iconScale
		height: 23 * root.device.percentage * root.iconScale
		radius: 2 * root.iconScale

		color: root.isPluggedIn ? "#359040"
		     : ShellGlobals.interpolateColors(Math.min(1.0, Math.min(0.5, root.device.percentage) * 2), "red", "white")
	}

	Image {
		id: img
		anchors.fill: parent;

		source: root.isCharging ? "root:icons/battery-charging.svg"
		      : root.isPluggedIn ? "root:icons/battery-plus.svg"
					: root.isLow ? "root:icons/battery-warning.svg"
		      : "root:icons/battery-empty.svg"

		sourceSize.width: parent.width
		sourceSize.height: parent.height
		visible: true
	}
}
