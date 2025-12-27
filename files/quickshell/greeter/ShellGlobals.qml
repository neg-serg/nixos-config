pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

Singleton {
	id: root
	readonly property string rtpath: "/tmp/quickshell-greeter"

	readonly property var colors: QtObject {
		readonly property color bar: "#30c0ffff";
		readonly property color barOutline: "#50ffffff";
		readonly property color widget: "#25ceffff";
		readonly property color widgetActive: "#80ceffff";
		readonly property color widgetOutline: "#40ffffff";
		readonly property color widgetOutlineSeparate: "#20ffffff";
		readonly property color separator: "#60ffffff";
	}

	readonly property var popoutXCurve: EasingCurve {
		id: xCurve
		curve.type: Easing.OutQuint
	}

	readonly property var popoutYCurve: EasingCurve {
		id: yCurve
		curve.type: Easing.InQuart
	}

	function interpolateColors(x: real, a: color, b: color): color {
		const xa = 1.0 - x;
		return Qt.rgba(a.r * xa + b.r * x, a.g * xa + b.g * x, a.b * xa + b.b * x, a.a * xa + b.a * x);
	}
}
