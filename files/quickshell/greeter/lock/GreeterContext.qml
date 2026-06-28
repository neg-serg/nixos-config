import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Greetd
import qs

Scope {
	id: root
	signal launch();

	property bool testMode: false

	// User and session selection
	property var users: []
	property int currentUserIndex: 0
	property var allSessions: []
	property int currentSessionIndex: 0

	// Sessions filtered by current user's allowed session type
	readonly property var sessions: {
		const utype = userSessionType[currentUser] || "wayland";
		return allSessions.filter(s => s.type === utype);
	}

	// Map user → session type. Users not listed default to "wayland".
	// Managed declaratively: add new users here when their session type is known.
	readonly property var userSessionType: ({
		"neg": "wayland",
		"xen": "x11"
	})

	readonly property string currentUser: users.length > 0 ? users[currentUserIndex] : "neg"
	readonly property string currentSessionName: sessions.length > 0 ? sessions[currentSessionIndex].name : "Hyprland"
	readonly property string currentSessionExec: sessions.length > 0 ? sessions[currentSessionIndex].exec : ""

	function cycleUser() {
		if (users.length > 1) {
			currentUserIndex = (currentUserIndex + 1) % users.length;
			currentSessionIndex = 0;
		}
	}

	function cycleSession() {
		if (sessions.length > 1)
			currentSessionIndex = (currentSessionIndex + 1) % sessions.length;
	}

	// Read login users from /etc/passwd (uid >= 1000, has valid shell)
	Process {
		id: userProc
		command: ["sh", "-c", "awk -F: '$3 >= 1000 && $3 < 60000 && $7 !~ /nologin|false/ {print $1}' /etc/passwd | sort"]
		running: true
		stdout: SplitParser {
			onRead: data => {
				const u = data.trim();
				if (u) root.users = root.users.concat([u]);
			}
		}
	}

	// Read sessions from .desktop files, tagged by type (wayland/x11)
	Process {
		id: sessionProc
		command: ["sh", "-c",
			"for f in /usr/share/wayland-sessions/*.desktop; do " +
			"[ -f \"$f\" ] && printf 'wayland\\t%s\\t%s\\n' " +
			"\"$(sed -n 's/^Name=//p' \"$f\" | head -1)\" " +
			"\"$(sed -n 's/^Exec=//p' \"$f\" | head -1)\"; done; " +
			"for f in /usr/share/xsessions/*.desktop; do " +
			"[ -f \"$f\" ] && printf 'x11\\t%s\\t%s\\n' " +
			"\"$(sed -n 's/^Name=//p' \"$f\" | head -1)\" " +
			"\"$(sed -n 's/^Exec=//p' \"$f\" | head -1)\"; done"
		]
		running: true
		stdout: SplitParser {
			onRead: data => {
				const parts = data.split("\t");
				if (parts.length === 3 && parts[1] && parts[2])
					root.allSessions = root.allSessions.concat([{type: parts[0], name: parts[1], exec: parts[2]}]);
			}
		}
	}

	property LockState state: LockState {
		onTryPasswordUnlock: {
			isUnlocking = true;
			if (root.testMode) {
				testAuthTimer.start();
			} else {
				Greetd.createSession(root.currentUser);
			}
		}
	}

	Timer {
		id: testAuthTimer
		interval: GreeterTheme.contextTimerMs
		onTriggered: {
			root.state.isUnlocking = false;
			root.launch();
		}
	}

	Connections {
		target: Greetd

		function onAuthMessage(message: string, error: bool, responseRequired: bool, echoResponse: bool) {
			if (responseRequired) {
				Greetd.respond(root.state.currentText);
			} // else ignore - only supporting passwords
		}

		function onAuthFailure() {
			root.state.currentText = "";
			root.state.error = "Invalid password";
			root.state.failed = true;
			root.state.isUnlocking = false;
		}

		function onReadyToLaunch() {
			root.state.isUnlocking = false;
			root.launch();
		}
	}
}
