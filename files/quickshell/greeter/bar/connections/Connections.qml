import QtQuick
import QtQuick.Layouts
import qs.bar

BarWidgetInner {
	id: root
	required property var bar;
	implicitHeight: column.implicitHeight + 10

	ColumnLayout {
		id: column

		anchors {
			fill: parent
			margins: 5
		}

		Bluetooth {
			Layout.fillWidth: true
			bar: root.bar
		}
	}
}
