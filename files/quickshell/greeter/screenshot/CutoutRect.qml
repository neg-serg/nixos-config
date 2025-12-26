pragma ComponentBehavior: Bound
import QtQuick

Item {
	id: root
	property color backgroundColor: "#20ffffff"
	property real backgroundOpacity: 1.0
	property alias innerBorderColor: center.border.color
	property alias innerX: center.x
	property alias innerY: center.y
	property alias innerW: center.width
	property alias innerH: center.height

	Rectangle {
		id: center
		border.color: "white"
		border.width: 2
		color: "transparent"
	}

	Rectangle {
		id: topOverlay
		color: root.backgroundColor
		opacity: root.backgroundOpacity

		anchors {
			top: root.top
			left: root.left
			right: root.right
			bottom: center.top
		}
	}

	Rectangle {
		id: bottomOverlay
		color: root.backgroundColor
		opacity: root.backgroundOpacity

		anchors {
			top: center.bottom
			left: root.left
			right: root.right
			bottom: root.bottom
		}
	}

	Rectangle {
		id: leftOverlay
		color: root.backgroundColor
		opacity: root.backgroundOpacity

		anchors {
			top: center.top
			left: root.left
			right: center.left
			bottom: center.bottom
		}
	}

	Rectangle {
		id: rightOverlay
		color: root.backgroundColor
		opacity: root.backgroundOpacity

		anchors {
			top: center.top
			left: center.right
			right: root.right
			bottom: center.bottom
		}
	}
}
