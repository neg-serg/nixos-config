// Preview harness for the login card: `qs -p files/quickshell/greeter/preview.qml`.
//
// It hosts the real lock/LockContent.qml in a plain floating window with a
// LockState of its own — no greetd, no ext-session-lock, nothing to log into — so
// the screen can be looked at and screenshotted while a session is running. The
// wallpaper is the file the login layer itself shows
// (~/.cache/greeter-wallpaper; override with PREVIEW_WALLPAPER). The field is
// live, so typing and Enter go through the real PAM path — the card only cannot
// hand the session over. The compositor tiles the window like any other, so run
// it on an empty workspace unless the layout is wanted.
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs
import qs.lock
import qs.background

ShellRoot {
	FloatingWindow {
		id: win
		implicitWidth: 1280
		implicitHeight: 720
		color: "#000000"

		BackgroundImage {
			id: backdrop
			anchors.fill: parent
			screen: win.screen
			slideAmount: 0
			asynchronous: false
			wallpaperPath: Quickshell.env("PREVIEW_WALLPAPER")
			|| ("file://" + (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/greeter-wallpaper")
		}

		CrtBackdrop {
			anchors.fill: parent
			visible: GreeterTheme.crtEnabled
			backdrop: backdrop
		}

		LockContent {
			anchors.fill: parent
			state: LockState {
				id: previewState
			}
			backdrop: backdrop
			layoutName: Quickshell.env("PREVIEW_LAYOUT") || "US"
		}
	}
}
