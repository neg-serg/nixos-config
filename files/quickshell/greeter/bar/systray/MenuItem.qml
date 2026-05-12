pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.DBusMenu
import qs

MouseArea {
	id: root
	required property QsMenuEntry entry;
	property alias expanded: childrenRevealer.expanded;
	property bool animating: childrenRevealer.animating || (childMenuLoader?.item?.animating ?? false);
	// appears it won't actually create the handler when only used from MenuItemList.
	onExpandedChanged: {}
	onAnimatingChanged: {}

	signal close();

	implicitWidth: row.implicitWidth + 4
	implicitHeight: row.implicitHeight + 4

	hoverEnabled: true
	onClicked: {
		if (root.entry.hasChildren) root.childrenRevealer.expanded = !root.childrenRevealer.expanded
		else {
			root.entry.triggered();
			root.close();
		}
	}

	ColumnLayout {
		id: row
		anchors.fill: root
		anchors.margins: 2
		spacing: 0

		RowLayout {
			id: innerRow

			Item {
				id: iconWrapper
				implicitWidth: 22
				implicitHeight: 22

				MenuCheckBox {
					id: checkBox
					anchors.centerIn: iconWrapper
					visible: root.entry.buttonType === QsMenuButtonType.CheckBox
					checkState: root.entry.checkState
				}

				MenuRadioButton {
					id: radioButton
					anchors.centerIn: iconWrapper
					visible: root.entry.buttonType === QsMenuButtonType.RadioButton
					checkState: root.entry.checkState
				}

				MenuChildrenRevealer {
					id: childrenRevealer
					anchors.centerIn: iconWrapper
					visible: root.entry.hasChildren
					onOpenChanged: root.entry.showChildren = open
				}
			}

			Text {
				id: label
				text: root.entry.text
				color: root.entry.enabled ? "white" : "#bbbbbb"
			}

			Item {
				id: spacer
				Layout.fillWidth: true
				implicitWidth: 22
				implicitHeight: 22

				IconImage {
					id: icon
					anchors.right: spacer.right
					anchors.verticalCenter: spacer.verticalCenter
					source: root.entry.icon
					visible: icon.source !== ""
					implicitSize: spacer.height
				}
			}
		}

		Loader {
			id: childMenuLoader
			Layout.fillWidth: true
			Layout.preferredHeight: childMenuLoader.active ? (childMenuLoader.item?.implicitHeight ?? 0) * root.childrenRevealer.progress : 0

			readonly property real widthDifference: {
				Math.max(0, (childMenuLoader.item?.implicitWidth ?? 0) - innerRow.implicitWidth);
			}
			Layout.preferredWidth: childMenuLoader.active ? innerRow.implicitWidth + (childMenuLoader.widthDifference * root.childrenRevealer.progress) : 0

			active: root.expanded || root.animating
			clip: true

			sourceComponent: MenuView {
				id: childrenList
				menu: root.entry
				onClose: root.close()

				anchors {
					top: childMenuLoader.top
					left: childMenuLoader.left
					right: childMenuLoader.right
				}
			}
		}
	}

	Rectangle {
		id: background
		anchors.fill: root
		visible: root.containsMouse || root.childrenRevealer.expanded

		color: ShellGlobals.colors.widget
		border.width: 1
		border.color: ShellGlobals.colors.widgetOutline
		radius: 5
	}
}
