pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Greetd
import "background"
import "lock"

ShellRoot {
	id: root

	GreeterContext {
		id: context

		onLaunch: {
			lock.locked = false;
			Greetd.launch(["/etc/greetd/session-wrapper"]);
		}
	}

	WlSessionLock {
		id: lock
		locked: true

		WlSessionLockSurface {
			id: lockSurface
			color: "darkgreen"

			BackgroundImage {
				id: backgroundImage
				anchors.fill: parent
				screen: lockSurface.screen
			}

			LockContent {
				anchors.fill: parent
				state: context.state
			}
		}
	}
}
