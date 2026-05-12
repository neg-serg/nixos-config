pragma ComponentBehavior: Bound
import QtQuick

Item {
	id: root
	onChildrenChanged: root.recalc();

	Instantiator {
		id: childMonitor
		model: root.children

		Connections {
			id: childConnection
			required property Item modelData;
			target: childConnection.modelData;

			function onImplicitHeightChanged() {
				root.recalc();
			}

			function onImplicitWidthChanged() {
				root.recalc();
			}
		}
	}

	function recalc() {
		let y = 0
		let w = 0
		for (let i = 0; i < root.children.length; i++) {
			const child = root.children[i];
			child.y = y;
			y += child.implicitHeight
			if (child.implicitWidth > w) w = child.implicitWidth;
		}

		root.implicitHeight = y;
		root.implicitWidth = w;
	}
}
