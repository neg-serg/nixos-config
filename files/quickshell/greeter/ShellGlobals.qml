pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

// NOTE: The greeter runs as an isolated QML module with its own qmldir.
// It does NOT import qs.Settings or Theme — the greeter must work without
// the user's config (e.g. on first boot, locked screen with no session).
// Colors are now read from GreeterTheme (which reads Theme/.theme.json)
// with hardcoded fallback defaults for when the file is unavailable.
Singleton {
	id: root
	readonly property string rtpath: "/tmp/quickshell-greeter"

	readonly property var colors: QtObject {
		readonly property color bar: GreeterTheme.barColor
		readonly property color barOutline: GreeterTheme.barOutline
		readonly property color widget: GreeterTheme.widgetColor
		readonly property color widgetActive: GreeterTheme.widgetActiveColor
		readonly property color widgetOutline: GreeterTheme.widgetOutline
		readonly property color widgetOutlineSeparate: GreeterTheme.widgetOutlineSeparate
		readonly property color separator: GreeterTheme.separatorColor
	}

	function interpolateColors(x: real, a: color, b: color): color {
		const xa = 1.0 - x;
		return Qt.rgba(a.r * xa + b.r * x, a.g * xa + b.g * x, a.b * xa + b.b * x, a.a * xa + b.a * x);
	}
}
