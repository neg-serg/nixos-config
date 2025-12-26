pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

Scope {
	id: root

	required property Component renderComponent;

	property bool inTray: false;
	property bool destroyOnInvisible: false;
	property int visualizerCount: 0;
	property FlickableNotification visualizer;

	signal dismiss();
	signal discard();
	signal discarded();

	function handleDismiss() {}
	function handleDiscard() {}

	onVisualizerChanged: {
		if (!root.visualizer) {
			expireAnim.stop();
			root.timePercentage = 1;
		}

		if (!root.visualizer && root.destroyOnInvisible) root.destroy();
	}

	function untrack() {
		root.destroyOnInvisible = true;
		if (!root.visualizer) root.destroy();
	}

	property int expireTimeout: -1
	property real timePercentage: 1
	property int pauseCounter: 0
	readonly property bool shouldPause: root.pauseCounter !== 0 || (NotificationManager.lastHoveredNotif?.pauseCounter ?? 0) !== 0

	onPauseCounterChanged: {
		if (root.pauseCounter > 0) {
			NotificationManager.lastHoveredNotif = root;
		}
	}

	NumberAnimation on timePercentage {
		id: expireAnim
		running: root.expireTimeout !== 0
		paused: expireAnim.running && root.shouldPause && expireAnim.to === 0
		duration: root.expireTimeout === -1 ? 10000 : root.expireTimeout
		to: 0
		onFinished: {
			if (!root.inTray) root.dismiss();
		}
	}

	onInTrayChanged: {
		if (root.inTray) {
			expireAnim.stop();
			expireAnim.duration = 300 * (1 - root.timePercentage);
			expireAnim.to = 1;
			expireAnim.start();
		}
	}
}
