import QtQuick
import qs.components

Item {
	id: root
	property real from: 0.0
	property real to: 1.5
	property real warning: 1.0
	property real value: 0.0

	implicitWidth: groove.implicitWidth
	implicitHeight: 20

	property real __valueOffset: ((value - from) / (to - from)) * groove.width
	property real __wheelValue: -1

	MouseArea {
		id: mouseArea
		anchors.fill: parent

		Rectangle {
			id: grooveWarning

			anchors {
				left: groove.left
				leftMargin: ((warning - from) / (to - from)) * groove.width
				right: groove.right
				top: groove.top
				bottom: groove.bottom
			}

			color: "#60ffa800"
			topRightRadius: 5
			bottomRightRadius: 5
		}

		Rectangle {
			anchors {
				top: groove.bottom
				horizontalCenter: grooveWarning.left
			}

			color: "#60eeffff"
			width: 1
			height: groove.height
		}

		GrooveTrack {
			id: groove

			anchors {
				left: parent.left
				right: parent.right
				verticalCenter: parent.verticalCenter
			}

			fillWidth: __valueOffset
			grooveBorderColor: "#20050505"
			showHandle: true
		}

		onWheel: event => {
			event.accepted = true;
			__wheelValue = value + (event.angleDelta.y / 120) * 0.05;
			// Defer the sentinel reset so the Binding above can apply the value
			// (and its onValueChanged write-back) before RestoreBinding runs.
			Qt.callLater(function() { root.__wheelValue = -1; });
		}
	}

	Binding {
		when: mouseArea.pressed
		target: root
		property: "value"
		value: (mouseArea.mouseX / width) * (to - from) + from
		restoreMode: Binding.RestoreBinding
	}

	Binding {
		when: __wheelValue != -1
		target: root
		property: "value"
		value: __wheelValue
		restoreMode: Binding.RestoreBinding
	}
}
