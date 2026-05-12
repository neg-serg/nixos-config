pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.bar

BarWidgetInner {
	id: root
	required property var bar;

	property bool controlsOpen: false;
	onControlsOpenChanged: NotificationManager.showTrayNotifs = root.controlsOpen;

	Connections {
		id: managerConnection
		target: NotificationManager

		function onHasNotifsChanged() {
			if (!NotificationManager.hasNotifs) {
				root.controlsOpen = false;
			}
		}
	}

	implicitHeight: root.width

	BarButton {
		id: button
		anchors.fill: root
		baseMargin: 8
		fillWindowWidth: true
		acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
		showPressed: root.controlsOpen || (button.pressedButtons & ~Qt.RightButton)

		Image {
			id: bellIcon
			anchors.fill: button

			source: NotificationManager.hasNotifs
				? "root:icons/bell-fill.svg"
				: "root:icons/bell.svg"

			fillMode: Image.PreserveAspectFit

			sourceSize.width: bellIcon.width
			sourceSize.height: bellIcon.height
		}

		onPressed: event => {
			if (event.button === Qt.RightButton && NotificationManager.hasNotifs) {
				root.controlsOpen = !root.controlsOpen;
			}
		}
	}

	property TooltipItem tooltip: TooltipItem {
		id: widgetTooltip
		tooltip: root.bar.tooltip
		owner: root
		show: button.containsMouse

		Label {
			id: tooltipLabel
			anchors.verticalCenter: widgetTooltip.verticalCenter
			text: {
				const count = NotificationManager.notifications.length;
				return count === 0 ? "No notifications"
					: count === 1 ? "1 notification"
					: `${count} notifications`;
			}
		}
	}

	property TooltipItem rightclickMenu: TooltipItem {
		id: widgetMenu
		tooltip: root.bar.tooltip
		owner: root
		isMenu: true
		grabWindows: [NotificationManager.overlay]
		show: root.controlsOpen
		onClose: root.controlsOpen = false

		Item {
			id: menuContainer
			implicitWidth: 440
			implicitHeight: root.implicitHeight - 10

			MouseArea {
				id: closeArea

				anchors {
					right: menuContainer.right
					rightMargin: 5
					verticalCenter: menuContainer.verticalCenter
				}

				implicitWidth: 30
				implicitHeight: 30

				hoverEnabled: true
				onPressed: {
					NotificationManager.sendDiscardAll()
				}

				Rectangle {
					id: closeBackground
					anchors.fill: closeArea
					anchors.margins: 5
					radius: closeBackground.width * 0.5
					antialiasing: true
					color: "#60ffffff"
					opacity: closeArea.containsMouse ? 1 : 0
					Behavior on opacity { SmoothedAnimation { velocity: 8 } }
				}

				CloseButton {
					id: closeButton
					anchors.fill: closeArea
					ringFill: 0 // root.backer?.timePercentage ?? 0
				}
			}
		}
	}
}
