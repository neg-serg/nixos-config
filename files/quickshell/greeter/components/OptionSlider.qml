pragma ComponentBehavior: Bound;

import QtQuick

Item {
	id: root

	property list<string> values;
	property int index: 0;

	implicitWidth: 300
	implicitHeight: 40

	MouseArea {
		id: mouseArea
		anchors.fill: root

		property real halfHandle: handle.width / 2;
		property real activeWidth: groove.width - handle.width;
		property real valueOffset: mouseArea.halfHandle + (root.index / (root.values.length - 1)) * mouseArea.activeWidth;

		Repeater {
			id: repeater
			model: root.values

			Item {
				id: delegate
				required property int index;
				required property string modelData;

				anchors.top: groove.bottom
				anchors.topMargin: 2
				x: mouseArea.halfHandle + (delegate.index / (root.values.length - 1)) * mouseArea.activeWidth

				Rectangle {
					id: mark
					color: "#60eeffff"
					width: 1
					height: groove.height
				}

				Text {
					id: delegateText
					anchors.top: mark.bottom

					x: delegate.index === 0 ? -4
					 : delegate.index === root.values.length - 1 ? -delegateText.width + 4
					 : -(delegateText.width / 2);

					text: delegate.modelData
					color: "#a0eeffff"
				}
			}
		}

		Rectangle {
			id: grooveFill

			anchors {
				left: groove.left
				top: groove.top
				bottom: groove.bottom
			}

			radius: 5
			color: "#80ceffff"
			width: mouseArea.valueOffset
		}

		Rectangle {
			id: groove

			anchors {
				left: mouseArea.left
				right: mouseArea.right
			}

			y: 5
			implicitHeight: 7
			color: "transparent"
			border.color: "#20eeffff"
			border.width: 1
			radius: 5
		}

		Rectangle {
			id: handle
			anchors.verticalCenter: groove.verticalCenter
			height: 15
			width: handle.height
			radius: handle.height * 0.5
			x: mouseArea.valueOffset - handle.width * 0.5
		}
	}

	Binding {
		id: indexBinding
		when: mouseArea.pressed
		target: root
		property: "index"
		value: Math.max(0, Math.min(root.values.length - 1, Math.round((mouseArea.mouseX / root.width) * (root.values.length - 1))))
		restoreMode: Binding.RestoreBinding
	}
}
