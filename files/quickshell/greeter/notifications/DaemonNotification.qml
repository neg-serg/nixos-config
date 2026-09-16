pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Notifications

TrackedNotification {
	id: root
	required property Notification notif;

	renderComponent: StandardNotificationRenderer {
		id: renderer
		notif: root.notif
		backer: root
	}

	function handleDiscard() {
		if (!lock.retained) root.notif.dismiss();
		root.discarded();
	}

	function handleDismiss() {
		// Base TrackedNotification behavior: mark the tracked object discarded
		// so the manager removes it. The previous empty body left a dangling
		// backer.visualizer until the next notification.
		root.discard();
	}

	RetainableLock {
		id: lock
		object: root.notif
		locked: true
		onRetainedChanged: {
			if (lock.retained) root.discard();
		}
	}

	expireTimeout: root.notif.expireTimeout
}
