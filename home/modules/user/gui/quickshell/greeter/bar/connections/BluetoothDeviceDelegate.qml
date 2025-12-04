import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Widgets
import Quickshell.Bluetooth
import qs
import qs.bar

WrapperMouseArea {
	id: root
	required property BluetoothDevice device
	property bool menuOpen: false
	readonly property bool showBg: false//pairingContext.attentionRequested //device.connected//menuOpen //|| containsMouse
	hoverEnabled: true

	onClicked: menuOpen = !menuOpen

	WrapperRectangle {
		color: root.showBg ? ShellGlobals.colors.widget : "transparent"
		border.width: 1
		border.color: root.showBg ? ShellGlobals.colors.widgetOutline : "transparent"
		radius: 4
		rightMargin: 2

		ColumnLayout {
			RowLayout {
				ClickableIcon {
					image: Quickshell.iconPath(root.device.icon)
					implicitHeight: 40
					implicitWidth: height
				}

				Label {
					text: root.device.name
				}

				Item { Layout.fillWidth: true }

				ActivityButton {
					image: root.device.connected ? "root:/icons/plugs-connected.svg" : "root:/icons/plugs.svg"
					implicitHeight: 24
					implicitWidth: height
					showAction: root.device.pairing || root.device.state === BluetoothDeviceState.Connecting || root.device.state === BluetoothDeviceState.Disconnecting
					onClicked: {
						if (showAction) return;
						else if (root.device.connected) root.device.disconnect();
						else if (root.device.paired) root.device.connect();
						else root.device.pair();
					}
				}

				ClickableIcon {
					image: "root:/icons/trash.svg"
					implicitHeight: 24
					implicitWidth: height
					visible: root.device.bonded
					onClicked: root.device.forget()
				}
			}

			/*RowLayout {
				Layout.margins: 3
				Layout.topMargin: 0
				visible: root.showBg

				BluetoothPairingContext {
					id: pairingContext
					device: root.device
				}

				Label {
					text: `Pairing Code: ${pairingContext.pairingCode}`
				}

				Button {
					text: "Accept"
					onClicked: pairingContext.confirmCode(true)
				}

				Button {
					text: "Reject"
					onClicked: pairingContext.confirmCode(false)
				}
			}*/
		}
	}
}
