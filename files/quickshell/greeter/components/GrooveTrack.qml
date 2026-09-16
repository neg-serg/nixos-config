import QtQuick

// Shared greeter slider track: a translucent fill beneath a bordered groove,
// with an optional round handle. The root box is the groove itself, so callers
// anchor to it exactly as they did to the old inline `groove` rectangle.
Item {
	id: root

	property color grooveBorderColor: "#20eeffff"
	property color fillColor: "#80ceffff"
	property real fillWidth: 0
	property bool showHandle: false
	readonly property real handleWidth: 15

	implicitHeight: 7
	height: implicitHeight

	Rectangle {
		id: grooveFill

		anchors {
			left: parent.left
			top: parent.top
			bottom: parent.bottom
		}

		radius: 5
		color: root.fillColor
		width: root.fillWidth
	}

	Rectangle {
		id: groove

		anchors {
			left: parent.left
			right: parent.right
			verticalCenter: parent.verticalCenter
		}

		implicitHeight: 7
		color: "transparent"
		border.color: root.grooveBorderColor
		border.width: 1
		radius: 5
	}

	Rectangle {
		id: handle

		visible: root.showHandle
		anchors.verticalCenter: parent.verticalCenter
		height: root.handleWidth
		width: height
		radius: height * 0.5
		x: root.fillWidth - width * 0.5
	}
}
