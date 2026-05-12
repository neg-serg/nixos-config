pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Services.SystemTray
import qs.bar

BarWidgetInner {
	id: root
	required property var bar;
	implicitHeight: column.implicitHeight + 10

	ColumnLayout {
		id: column
		implicitHeight: column.childrenRect.height
		spacing: 5

		anchors {
			fill: root
			margins: 5
		}

		Repeater {
			id: trayRepeater
			model: SystemTray.items;

			Item {
				id: trayItem
				required property SystemTrayItem modelData;

				property bool targetMenuOpen: false;

				Layout.fillWidth: true
				implicitHeight: trayItem.width

				ClickableIcon {
					id: mouseArea
					anchors {
						top: trayItem.top
						bottom: trayItem.bottom
						horizontalCenter: trayItem.horizontalCenter
					}
					width: mouseArea.height

					acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

					image: trayItem.modelData.icon
					showPressed: trayItem.targetMenuOpen || (mouseArea.pressedButtons & ~Qt.RightButton)
					fillWindowWidth: true
					extraVerticalMargin: column.spacing / 2

					onClicked: event => {
						event.accepted = true;

						if (event.button === Qt.LeftButton) {
							trayItem.modelData.activate();
						} else if (event.button === Qt.MiddleButton) {
							trayItem.modelData.secondaryActivate();
						}
					}

					onPressed: event => {
						if (event.button === Qt.RightButton && trayItem.modelData.hasMenu) {
							trayItem.targetMenuOpen = !trayItem.targetMenuOpen;
						}
					}

					onWheel: event => {
						event.accepted = true;
						const points = event.angleDelta.y / 120
						trayItem.modelData.scroll(points, false);
					}

					property var tooltip: TooltipItem {
						id: trayTooltip
						tooltip: root.bar.tooltip
						owner: mouseArea

						show: mouseArea.containsMouse

						Text {
							id: tooltipText
							text: trayItem.modelData.tooltipTitle !== "" ? trayItem.modelData.tooltipTitle : trayItem.modelData.id
							color: "white"
						}
					}

					property var rightclickMenu: TooltipItem {
						id: trayRightclickMenu
						tooltip: root.bar.tooltip
						owner: mouseArea

						isMenu: true
						show: trayItem.targetMenuOpen
						animateSize: !(menuContentLoader?.item?.animating ?? false)

						onClose: trayItem.targetMenuOpen = false;

						Loader {
							id: menuContentLoader
							active: trayItem.targetMenuOpen || trayRightclickMenu.visible || mouseArea.containsMouse

							sourceComponent: MenuView {
								id: menuView
								menu: trayItem.modelData.menu
								onClose: trayItem.targetMenuOpen = false;
							}
						}
					}
				}
			}
		}
	}
}
