pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Singleton {
	id: root
	signal screenshot();

	IpcHandler {
		id: handler
		target: "screenshot"
		function takeScreenshot() { root.screenshot(); }
	}
}
