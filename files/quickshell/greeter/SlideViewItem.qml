pragma ComponentBehavior: Bound
import Quickshell
import QtQuick

QtObject {
	id: root
	required property Item item;
	property Animation activeAnimation: null;
	signal animationCompleted(self: SlideViewItem);

	property Connections __animConnection: Connections {
		target: root.activeAnimation

		function onStopped() {
			root.activeAnimation.destroy();
			root.animationCompleted(root);
		}
	}

	function createAnimation(component: Component) {
		root.stopIfRunning();
		root.activeAnimation = component.createObject(root, { target: root.item });
		root.activeAnimation.running = true;
	}

	function stopIfRunning() {
		if (root.activeAnimation) {
			root.activeAnimation.stop();
			root.activeAnimation = null;
		}
	}

	function finishIfRunning() {
		if (root.activeAnimation) {
			// animator types dont handle complete correctly.
			root.activeAnimation.complete();
			root.activeAnimation.stop();
			root.item.x = 0;
			root.item.y = 0;
			root.activeAnimation = null;
		}
	}

	function destroyAll() {
		root.item.destroy();
		root.destroy();
	}
}
