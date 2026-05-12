pragma ComponentBehavior: Bound
import QtQuick

// kind of like a lighter StackView which handles replacement better.
Item {
	id: root

	property Component enterTransition: XAnimator {
		id: enterAnimator
		from: root.width
		duration: 3000
	}

	property Component exitTransition: XAnimator {
		id: exitAnimator
		to: (exitAnimator.target ? exitAnimator.target.x - exitAnimator.target.width : 0)
		duration: 3000
	}

	property bool animate: root.visible;

	onAnimateChanged: {
		if (!root.animate) root.finishAnimations();
	}

	property Component itemComponent: SlideViewItem {}
	property SlideViewItem activeItem: null;
	property Item pendingItem: null;
	property bool pendingNoAnim: false;
	property list<SlideViewItem> removingItems;

	readonly property bool animating: root.activeItem && root.activeItem.activeAnimation !== null

	function replace(component: Component, defaults: var, noanim: bool) {
		root.pendingNoAnim = noanim;

		if (component) {
			const props = defaults ?? {};
			props.parent = null;
			props.width = Qt.binding(() => root.width);
			props.height = Qt.binding(() => root.height);

			const item = component.createObject(root, props);
			if (root.pendingItem) root.pendingItem.destroy();
			root.pendingItem = item;
			const ready = item?.svReady ?? true;
			if (ready) root.finishPending();
		} else {
			root.finishPending(); // remove
		}
	}

	Connections {
		id: pendingConnection
		target: root.pendingItem

		function onSvReadyChanged() {
			if (root.pendingItem && root.pendingItem.svReady) {
				root.finishPending();
			}
		}
	}

	function finishPending() {
		const noanim = root.pendingNoAnim || !root.animate;
		if (root.activeItem) {
			if (noanim) {
				root.activeItem.destroyAll();
				root.activeItem = null;
			} else {
				root.removingItems.push(root.activeItem);
				root.activeItem.animationCompleted.connect(item => root.removeItem(item));
				root.activeItem.stopIfRunning();
				root.activeItem.createAnimation(root.exitTransition);
				root.activeItem = null;
			}
		}

		if (!root.animate) root.finishAnimations();

		if (root.pendingItem) {
			root.pendingItem.parent = root;
			root.activeItem = root.itemComponent.createObject(root, { item: root.pendingItem });
			root.pendingItem = null;
			if (!noanim) {
				root.activeItem.createAnimation(root.enterTransition);
			}
		}
	}

	function removeItem(item: SlideViewItem) {
		item.destroyAll();

		for (let i = 0; i !== root.removingItems.length; i++) {
			if (root.removingItems[i] === item) {
				root.removingItems.splice(i, 1);
				break;
			}
		}
	}

	function finishAnimations() {
		for (let i = 0; i < root.removingItems.length; i++) {
			root.removingItems[i].destroyAll();
		}
		root.removingItems = [];

		if (root.activeItem) {
			root.activeItem.finishIfRunning();
		}
	}

	Component.onDestruction: {
		for (let i = 0; i < root.removingItems.length; i++) {
			root.removingItems[i].destroyAll();
		}
		if (root.activeItem) root.activeItem.destroyAll();
		if (root.pendingItem) root.pendingItem.destroy();
	}
}
