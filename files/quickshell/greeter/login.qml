// Login layer — the login screen of the single-compositor session.
//
// A second quickshell instance inside the session compositor, started by
// files/gui/hypr/hyprland.lua while the wrapper's marker
// ($QS_LOGIN_STATE_DIR/state, see modules/user/session/greetd/session-wrapper.sh)
// reads "login". See modules/user/session/greetd/login-layer.sh — installed as
// `qs-login-layer`, which is what hyprland.lua runs.
//
//   login   — this layer owns the screen: the session-lock surface makes the
//             compositor route every key/mouse event here
//   session — the password was accepted, this process writes the marker and
//             exits, and hyprland.lua starts the desktop session
//
// Authentication reuses the greeter's PAM path (Quickshell.Services.Pam with
// lock/pam/password.conf below), so there is no setuid helper and no extra PAM
// session: greetd already opened the logind/PAM session for the main user before
// running the wrapper, and the compositor on screen is the one that will run the
// desktop. The only thing that changes on login is which process owns the
// screen — no greeter process exits, no second compositor, no DRM mode re-set.

pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Wayland
import "background"
import "lock"

ShellRoot {
	id: root

	// Runtime state shared with modules/user/session/greetd (the paths must
	// match). The wrapper exports QS_LOGIN_STATE_DIR so the compositor, this
	// layer and login-wallpaper.sh all agree on one directory; the fallback is
	// the wrapper's own, for a layer started by hand.
	readonly property string stateDir: {
		const env = Quickshell.env("QS_LOGIN_STATE_DIR");
		if (env && env !== "")
			return env;
		const rt = Quickshell.env("XDG_RUNTIME_DIR");
		return (rt && rt !== "" ? rt : ("/run/user/" + (Quickshell.env("UID") || ""))) + "/quickshell-login";
	}
	readonly property string statePath: root.stateDir + "/state"
	readonly property string wallpaperPathFile: root.stateDir + "/wallpaper"

	// Wallpaper: login-wallpaper.sh resolves the same source priority as the
	// session's own wallpaper, so login and desktop show the same image. Empty
	// means "not resolved yet" — BackgroundImage then paints its dot grid.
	property string wallpaperFile: ""

	FileView {
		id: wallpaperFileView
		path: root.wallpaperPathFile
		watchChanges: true
		blockLoading: false
		onLoaded: {
			const p = text().trim();
			root.wallpaperFile = p.length > 0 ? ("file://" + p) : "";
		}
		onFileChanged: wallpaperFileView.reload()
		onLoadFailed: root.wallpaperFile = ""
	}

	// Keyboard layout. While a session lock is up the compositor's binds do not
	// fire and kb_options is empty (files/gui/hypr/hyprland.lua), so there is no
	// way to change the layout at the login screen — a Latin password typed in a
	// Russian layout is simply rejected, with nothing in the UI hinting why
	// (2026-09-19 18:05: three attempts, no way out but to kill the layer).
	// `qs-login-layer` therefore puts the compositor on index 0 (`us`, the first
	// entry of kb_layout) before this file loads, and the chip in the corner
	// toggles it from inside the lock surface (the button in the corner). The label
	// is the layout we set, not a reading of the device: nothing else can change
	// it while the lock is up.
	property int layoutIndex: 0
	readonly property string layoutName: root.layoutIndex === 0 ? "US" : (root.layoutIndex === 1 ? "RU" : String(root.layoutIndex))

	Process {
		id: layoutSet
	}

	function setLayout(index) {
		root.layoutIndex = index;
		layoutSet.command = ["hyprctl", "switchxkblayout", "all", String(index)];
		layoutSet.running = true;
	}

	LockState {
		id: state

		onTryPasswordUnlock: {
			state.isUnlocking = true;
			pam.start();
		}
	}

	PamContext {
		id: pam
		// Relative to this file — the greeter's own PAM config
		// (files/quickshell/greeter/lock/pam/*.conf), unchanged, so the password
		// path is the same one a fresh login went through before. No new PAM
		// service and no authentication on greetd's side: the greetd session is
		// this user's already.
		configDirectory: "lock/pam"
		config: "password.conf"

		onPamMessage: {
			if (pam.responseRequired) {
				pam.respond(state.currentText);
			} else if (pam.messageIsError) {
				root.failLogin(pam.message + " — keymap " + root.layoutName);
			}
		}

		onCompleted: status => root.finishLogin(status === PamResult.Success)
	}

	// Mirrors the greeter's SessionLockContext, except that a successful PAM
	// result ends the login instead of launching a session: the compositor is
	// already ours.
	function finishLogin(success) {
		state.isUnlocking = false;
		if (!success) {
			// The layout is the one failure mode the UI cannot show on its own, so
			// it goes into the message (see the layout chip below).
			root.failLogin("Invalid password — keymap " + root.layoutName);
			return;
		}
		state.failed = false;
		state.error = "";
		root.writeState("session");
	}

	function failLogin(message) {
		state.currentText = "";
		state.error = message;
		state.failed = true;
		state.isUnlocking = false;
	}

	function writeState(value) {
		// A Process rather than FileView.setText: the marker has to be on disk —
		// and verified — before the screen is handed over, because hyprland.lua
		// reads it to decide whether the desktop may start. The `mkdir -p` is for a
		// layer started by hand, whose QS_LOGIN_STATE_DIR may not exist yet (under
		// greetd the wrapper creates it).
		//
		// `rm -f login-phase` is the systemd-visible half of the same marker: while
		// that file exists, quickshell.service and hypridle.service refuse to start
		// (ConditionPathExists=!%t/quickshell-login/login-phase), which keeps the
		// desktop out of the login screen even when nix-maid's sd-switch starts a
		// changed unit directly (see session-wrapper.sh). Removing it — after the
		// state file is written and verified — is what lets the desktop start.
		stateWriter.command = [
			"sh", "-c",
			"mkdir -p \"$(dirname \"$2\")\" 2> /dev/null; printf '%s\\n' \"$1\" > \"$2\" && [ \"$(cat \"$2\")\" = \"$1\" ] && rm -f \"$(dirname \"$2\")/login-phase\"",
			"login-state", value, root.statePath,
		];
		stateWriter.running = true;
	}

	Process {
		id: stateWriter

		onExited: code => {
			if (code !== 0) {
				// Nothing was recorded: keep the lock and say so instead of quitting
				// into a compositor whose config would decide on a marker that never
				// arrived (it would put the layer back up, or start no session at all).
				root.failLogin("Could not record the login");
				return;
			}
			// Unlock *before* quitting. Destroying a session-lock object while it is
			// still locked is a protocol violation: the compositor has to assume a
			// crashed lock client and may keep the session locked (quickshell warns
			// about exactly that on the way out). Unlocking first also leaves the
			// compositor free for the next attempt if this one never reaches the
			// desktop — hyprland.lua's retry loop needs to be able to take the lock
			// again.
			login.locked = false;
			// …and let the unlock reach the compositor before this process goes away.
			exitTimer.start();
		}
	}

	Timer {
		id: exitTimer
		interval: 80
		onTriggered: Qt.quit()
	}

	// ext-session-lock surface: while it exists the compositor paints nothing
	// else and routes every key/mouse event here — that is what makes this a
	// login screen and not an overlay, and it is also why no compositor keybind
	// can fire while the login screen is up.
	WlSessionLock {
		id: login

		locked: true

		WlSessionLockSurface {
			id: lockSurface
			color: "black"

			BackgroundImage {
				anchors.fill: parent
				screen: lockSurface.screen
				slideAmount: 0
				asynchronous: true
				wallpaperPath: root.wallpaperFile
			}

			LockContent {
				anchors.fill: parent
				state: state
				context: null
			}

			// Keyboard-layout button: shows which layout the password is being typed
			// in and switches it on click (see the layout note further up). A button
			// and not a hint, because a wrong layout is exactly the failure the rest
			// of the login screen cannot show: the password just comes back rejected.
			// Styled like the greeter's own lock buttons (ShellGlobals colours, same
			// hover interpolation, same 5 px radius).
			Rectangle {
				id: layoutButton

				anchors.right: parent.right
				anchors.bottom: parent.bottom
				anchors.margins: 40
				implicitWidth: layoutLabel.implicitWidth + 44
				implicitHeight: 48
				radius: 5
				border.width: 1
				border.color: ShellGlobals.colors.widgetOutline
				color: ShellGlobals.interpolateColors(
					layoutMouse.containsMouse || layoutMouse.pressed ? 1000 : 0,
					ShellGlobals.colors.widget,
					ShellGlobals.colors.widgetActive
				)

				Text {
					id: layoutLabel
					anchors.centerIn: parent
					text: "layout: " + root.layoutName
					color: "white"
					font.pixelSize: 20
				}

				MouseArea {
					id: layoutMouse
					anchors.fill: parent
					hoverEnabled: true
					cursorShape: Qt.PointingHandCursor
					onClicked: root.setLayout(root.layoutIndex === 0 ? 1 : 0)
				}
			}
		}
	}
}
