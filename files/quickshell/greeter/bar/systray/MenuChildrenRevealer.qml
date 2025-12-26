pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import Quickshell

Item {
	id: root
	property bool expanded: false;

	readonly property bool open: root.progress !== 0;
	readonly property bool animating: root.internalProgress !== (root.expanded ? 101 : -1);

	implicitHeight: 16
	implicitWidth: 16
	property var xStart: Math.round(root.width * 0.3)
	property var yStart: Math.round(root.height * 0.1)
	property var xEnd: Math.round(root.width * 0.7)
	property var yEnd: Math.round(root.height * 0.9)

	property real internalProgress: root.expanded ? 101 : -1;
	Behavior on internalProgress { SmoothedAnimation { velocity: 300 } }

	EasingCurve {
		id: curve
		curve.type: Easing.InOutQuad
	}

	readonly property real progress: curve.valueAt(Math.min(100, Math.max(root.internalProgress, 0)) * 0.01)

	rotation: root.progress * 90;

	Shape {
		id: revealShape
		anchors.fill: root

		layer.enabled: true
		layer.samples: 3

		ShapePath {
			id: revealPath
			strokeWidth: 2
			capStyle: ShapePath.RoundCap
			joinStyle: ShapePath.MiterJoin
			fillColor: "transparent"

			startX: root.xStart
			startY: root.yStart

			PathLine {
				id: pointLine
				x: root.xEnd
				y: root.height / 2
			}

			PathLine {
				id: returnLine
				y: root.yEnd
				x: root.xStart
			}
		}
	}
}
