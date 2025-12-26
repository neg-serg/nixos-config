pragma ComponentBehavior: Bound
import QtQuick
import qs

Rectangle {
	id: root
	property var checkState: Qt.Unchecked;
	implicitHeight: 18
	implicitWidth: 18
	radius: root.width / 2
	color: ShellGlobals.colors.widget

	Rectangle {
		id: innerCircle
		x: root.width * 0.25
		y: root.height * 0.25
		visible: root.checkState === Qt.Checked
		width: root.width * 0.5
		height: innerCircle.width
		radius: innerCircle.width / 2
	}
}
