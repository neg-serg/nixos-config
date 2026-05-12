import QtQuick
import QtQuick.Controls

ClickableIcon {
	id: root
	property bool showAction: false
	showPressed: mouseArea.pressed || showAction

	BusyIndicator {
		parent: root
		anchors.centerIn: parent
		opacity: root.showAction ? 1 : 0
		Behavior on opacity { SmoothedAnimation { velocity: 8 }}
		visible: opacity != 0
		width: root.width - 3 + opacity * 11
		height: width
		padding: 0
	}
}
