pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import qs

Rectangle {
	id: root
	property var checkState: Qt.Unchecked;
	implicitHeight: 18
	implicitWidth: 18
	radius: 3
	color: ShellGlobals.colors.widget

	Shape {
		id: checkShape
		visible: root.checkState === Qt.Checked
		anchors.fill: root
		layer.enabled: true
		layer.samples: 10

		ShapePath {
			id: checkPath
			strokeWidth: 2
			capStyle: ShapePath.RoundCap
			joinStyle: ShapePath.RoundJoin
			fillColor: "transparent"

			startX: startLine.x
			startY: startLine.y

			PathLine {
				id: startLine
				x: root.width * 0.8
				y: root.height * 0.2
			}

			PathLine {
				id: middleLine
				x: root.width * 0.35
				y: root.height * 0.8
			}

			PathLine {
				id: endLine
				x: root.width * 0.2
				y: root.height * 0.6
			}
		}
	}
}
