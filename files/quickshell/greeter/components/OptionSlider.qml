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

		property real halfHandle: groove.handleWidth / 2;
		property real activeWidth: groove.width - groove.handleWidth;
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

		GrooveTrack {
			id: groove

			anchors {
				left: mouseArea.left
				right: mouseArea.right
			}

			y: 5
			fillWidth: mouseArea.valueOffset
			showHandle: true
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
