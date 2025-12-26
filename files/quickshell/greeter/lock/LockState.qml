pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Mpris

Scope {
	id: root
	signal tryPasswordUnlock();
	property string currentText: "";
	property string error: "";
	property bool isUnlocking: false;
	property bool failed: false;
	property bool fprintAvailable: false;

	property bool fadedOut: false
	property real fadeOutMul: 0

	NumberAnimation on fadeOutMul {
		id: fadeAnim
		duration: 600
		easing.type: Easing.BezierSpline
		easing.bezierCurve: [0.0, 0.75, 0.15, 1.0, 1.0, 1.0]

		onStopped: {
			if (root.fadedOut) Hyprland.dispatch("dpms off");
		}
	}

	onCurrentTextChanged: {
		root.failed = false;
		root.error = "";

		if (root.fadedOut) {
			root.fadeIn();
		}
	}

	function fadeOut() {
		if (root.fadedOut) return;
		root.fadedOut = true;
		fadeAnim.to = 1;
		fadeAnim.restart();
	}

	function fadeIn() {
		if (!root.fadedOut) return;
		Hyprland.dispatch("dpms on");
		root.fadedOut = false;
		fadeAnim.to = 0;
		fadeAnim.restart();
	}

	ElapsedTimer { id: mouseTimer }

	// returns if mouse move should be continued, false should restart
	function mouseMoved(): bool {
		return root.mouseTimer.restart() < 0.2;
	}

	readonly property bool mediaPlaying: Mpris.players.values.some(player => {
		return player.playbackState === MprisPlaybackState.Playing && player.canPause;
	});

	function pauseMedia() {
		Mpris.players.values.forEach(player => {
			if (player.playbackState === MprisPlaybackState.Playing && player.canPause) {
				player.playbackState = MprisPlaybackState.Paused;
			}
		});
	}
}
