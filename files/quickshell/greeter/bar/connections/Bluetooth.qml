pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Widgets
import Quickshell.Bluetooth
import qs
import qs.bar

ClickableIcon {
	id: root
	required property var bar;
	readonly property BluetoothAdapter adapter: Bluetooth.defaultAdapter
	readonly property bool connected: adapter.devices.values.some(device => device.connected)

	property bool showMenu: false

	onPressed: event => {
		event.accepted = true;
		if (event.button === Qt.RightButton) {
			showMenu = !showMenu;
		}
	}

	onClicked: event => {
		if (event.button === Qt.LeftButton) {
			adapter.enabled = !adapter.enabled;
		}
	}

	showPressed: showMenu || (pressedButtons & ~Qt.RightButton)

	implicitHeight: width
	fillWindowWidth: true
	acceptedButtons: Qt.LeftButton | Qt.RightButton
	image: adapter.enabled
		? (connected ? "root:/icons/bluetooth-connected.svg" : "root:/icons/bluetooth.svg")
		: "root:/icons/bluetooth-slash.svg"

	property var tooltip: TooltipItem {
		tooltip: bar.tooltip
		owner: root
		show: root.containsMouse

		Label { text: "Bluetooth" }
	}

	property var rightclickMenu: TooltipItem {
		id: rightclickMenu
		tooltip: bar.tooltip
		owner: root

		isMenu: true
		show: root.showMenu
		onClose: root.showMenu = false

		Loader {
			width: 400
			active: root.showMenu || rightclickMenu.visible

			sourceComponent: Column {
				spacing: 5

				move: Transition {
					SmoothedAnimation { property: "y"; velocity: 350 }
				}

				RowLayout {
					width: parent.width

					ClickableIcon {
						image: root.image
						implicitHeight: 40
						implicitWidth: height
						onClicked: root.adapter.enabled = !root.adapter.enabled
					}

					Label {
						text: `Bluetooth (${root.adapter.adapterId})`
					}

					Item { Layout.fillWidth: true }

					ClickableIcon {
						image: root.adapter.enabled ? "root:/icons/bluetooth-slash.svg" : "root:/icons/bluetooth.svg"
						implicitHeight: 24
						implicitWidth: height
						onClicked: root.adapter.enabled = !root.adapter.enabled
					}

					ActivityButton {
						image: "root:/icons/binoculars.svg"
						implicitHeight: 24
						implicitWidth: height
						onClicked: root.adapter.discovering = !root.adapter.discovering
						showAction: root.adapter.discovering
						Layout.rightMargin: 4
					}
				}

				Rectangle {
					width: parent.width
					implicitHeight: 1
					visible: root.adapter.devices.values.length > 0

					color: ShellGlobals.colors.separator
				}

				Repeater {
					model: ScriptModel {
						values: [...root.adapter.devices.values].sort((a, b) => {
							if (a.connected && !b.connected) return -1;
							if (b.connected && !a.connected) return 1;
							if (a.bonded && !b.bonded) return -1;
							if (b.bonded && !a.bonded) return 1;
							return b.name - a.name;
						})
					}

					delegate: BluetoothDeviceDelegate {
						required property BluetoothDevice modelData
						device: modelData
						width: parent.width
					}
				}
			}
		}
	}
}
