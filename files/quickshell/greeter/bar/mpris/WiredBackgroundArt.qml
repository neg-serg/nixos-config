pragma ComponentBehavior: Bound

import QtQuick

// BackgroundArt wired to the active MPRIS track: it applies the current cover
// on completion and follows MprisController.trackChanged. `immediateOnComplete`
// preserves the right-click menu's immediate first paint.
BackgroundArt {
	id: root

	property bool immediateOnComplete: false

	Component.onCompleted: root.setArt(MprisController.activeTrack.artUrl, false, root.immediateOnComplete)

	Connections {
		target: MprisController

		function onTrackChanged(reverse: bool) {
			root.setArt(MprisController.activeTrack.artUrl, reverse, false);
		}
	}
}
