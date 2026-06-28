pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Greetd
import "background"
import "lock"

ShellRoot {
	id: root

	readonly property bool testMode: !Quickshell.env("GREETD_SOCK")
	// cage supports neither ext-session-lock-v1 nor wlr-layer-shell;
	// fall back to a plain FloatingWindow (cage auto-fullscreens it)
	readonly property bool useSessionLock: !testMode && Quickshell.env("GREETER_MODE") !== "cage"

	GreeterContext {
		id: context
		testMode: root.testMode

		onLaunch: {
			if (root.testMode) {
				Qt.quit();
			} else {
				if (root.useSessionLock) lock.locked = false;
				// Always route through session-wrapper so /etc/profile and
				// environment.d are sourced (greetd/PAM gives a bare env).
				const args = ["/etc/greetd/session-wrapper"];
				if (context.currentSessionExec)
					args.push(...context.currentSessionExec.split(" "));
				Greetd.launch(args);
			}
		}
	}

	// Session lock mode: compositors that support ext-session-lock-v1 (e.g. Hyprland)
	WlSessionLock {
		id: lock
		locked: root.useSessionLock

		WlSessionLockSurface {
			id: lockSurface
			color: "darkgreen"

			BackgroundImage {
				id: backgroundImage
				anchors.fill: parent
				screen: lockSurface.screen
				slideAmount: 0
			}

			LockContent {
				anchors.fill: parent
				state: context.state
				context: context
			}
		}
	}

	// Cage mode: regular toplevel window (cage auto-fullscreens it).
	// cage does not support wlr-layer-shell or ext-session-lock-v1,
	// so a plain FloatingWindow is the only option.
	FloatingWindow {
		id: cageWindow
		visible: !root.useSessionLock
		color: "darkgreen"

		BackgroundImage {
			anchors.fill: parent
			screen: cageWindow.screen
			slideAmount: 0
		}

		LockContent {
			anchors.fill: parent
			state: context.state
			context: context
		}
	}
}
