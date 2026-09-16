pragma ComponentBehavior: Bound
import QtQuick

Item {
	id: root

	property real from: 0.0
	property real to: 1.0
	property real value: 0.0

	implicitHeight: 7
	implicitWidth: 200

	GrooveTrack {
		id: groove

		anchors {
			left: root.left
			right: root.right
			verticalCenter: root.verticalCenter
		}

		height: 7
		fillWidth: root.width * ((root.value - root.from) / (root.to - root.from))
	}
}
