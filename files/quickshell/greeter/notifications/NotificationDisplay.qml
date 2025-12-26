pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import qs.components
import qs.shaders as Shaders

Item {
	id: root
	property list<Item> notifications: [];
	property list<Item> heightStack: [];

	property alias stack: stack;
	property alias topNotification: stack.topNotification;

	function addNotificationInert(notification: TrackedNotification): Item {
		const harness = stack._harnessComponent.createObject(stack, {
			backer: notification,
			view: root,
		});

		harness.contentItem = notification.renderComponent.createObject(harness);

		root.notifications = [...root.notifications, harness];
		root.heightStack = [harness, ...root.heightStack];

		return harness;
	}

	function addNotification(notification: TrackedNotification) {
		const harness = root.addNotificationInert(notification);
		harness.playEntry(0);
	}

	function dismissAll() {
		let delay = 0;

		for (const notification of root.notifications) {
			if (!notification.canDismiss) continue;
			notification.playDismiss(delay);
			notification.dismissed();
			delay += 0.025;
		}
	}

	function discardAll() {
		let delay = 0;

		for (const notification of root.notifications) {
			if (!notification.canDismiss) continue;
			notification.playDismiss(delay);
			notification.discarded();
			delay += 0.025;
		}
	}

	function addSet(notifications: list<TrackedNotification>) {
		let delay = 0;

		for (const notification of notifications) {
			if (notification.visualizer) {
				notification.visualizer.playReturn(delay);
			} else {
				const harness = root.addNotificationInert(notification);
				harness.playEntry(delay);
			}

			delay += 0.025;
		}
	}

	Item {
		id: contentLayer
		anchors.fill: root

		layer.enabled: stack.topNotification !== null
		layer.effect: Shaders.MaskedOverlay {
			id: maskedOverlay
			overlayItem: (stack.topNotification ? stack.topNotification.displayContainer : null)
			overlayPos: (stack.topNotification && maskedOverlay.overlayItem) ? Qt.point(stack.x + stack.topNotification.x + maskedOverlay.overlayItem.x, stack.y + stack.topNotification.y + maskedOverlay.overlayItem.y) : Qt.point(0, 0)
		}

		ZHVStack {
			id: stack

			property Item topNotification: {
				if (root.heightStack.length < 2) return null;
				const top = root.heightStack[0] ?? null;
				return (top && top.canOverlap) ? top : null;
			};

			property Component _harnessComponent: FlickableNotification {
				id: notificationDelegate
				required property TrackedNotification backer;

				edgeXOffset: -stack.x

				onDismissed: notificationDelegate.backer.handleDismiss();
				onDiscarded: notificationDelegate.backer.handleDiscard();

				onLeftViewBounds: {
					root.notifications = root.notifications.filter(n => n !== notificationDelegate);
					root.heightStack = root.heightStack.filter(n => n !== notificationDelegate);
					notificationDelegate.destroy();
				}

				onStartedFlick: {
					root.heightStack = [notificationDelegate, ...root.heightStack.filter(n => n !== notificationDelegate)];
				}

				Component.onCompleted: notificationDelegate.backer.visualizer = notificationDelegate;

				Connections {
					id: backerConnection
					target: notificationDelegate.backer

					function onDismiss() {
						notificationDelegate.playDismiss(0);
						notificationDelegate.dismissed();
					}

					function onDiscard() {
						notificationDelegate.playDismiss(0);
						notificationDelegate.discarded();
					}
				}
			}
		}
	}
}
