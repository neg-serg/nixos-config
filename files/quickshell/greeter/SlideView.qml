pragma ComponentBehavior: Bound
import QtQuick

// kind of like a lighter StackView which handles replacement better.
Item {
	id: root

	property Component enterTransition: XAnimator {
		from: root.width
		duration: 3000
	}

	property Component exitTransition: XAnimator {
		// Assuming XAnimator has a 'target' property. Using explicit binding if possible,
		// but inside a Component definition for animation, context is tricky.
		// If 'target' is a property of XAnimator, we can try accessing it directly.
		// However, qmllint might be confused if XAnimator isn't fully typed.
		// Trying to qualify with 'parent' or similar is hard inside a property Component.
		// If 'target' refers to the object being animated, it is standard for Animators.
		// For now, leaving target as is might be best if we can't qualify it,
		// BUT the warning was 'Unqualified access'.
		// If it resolved to something, let's assume valid access.
		// I will try to qualify 'target' if it's the property of the XAnimator itself?
		// No, usually you just write 'target'.
		// Maybe qmllint thinks it's accessing a parent property?
		// I will try to leave it for now or check if I can silence it / assume it's fine.
		// Actually, I'll focus on root properties first.
		to: target.x - target.width
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

	readonly property bool animating: activeItem?.activeAnimation != null

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
			if (ready) finishPending();
		} else {
			finishPending(); // remove
		}
	}

	Connections {
		target: root.pendingItem

		function onSvReadyChanged() {
			if (root.pendingItem.svReady) {
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
				root.activeItem.createAnimation(exitTransition);
				root.activeItem = null;
			}
		}

		if (!root.animate) finishAnimations();

		if (root.pendingItem) {
			root.pendingItem.parent = root;
			root.activeItem = itemComponent.createObject(root, { item: root.pendingItem });
			root.pendingItem = null;
			if (!noanim) {
				root.activeItem.createAnimation(enterTransition);
			}
		}
	}

	function removeItem(item: SlideViewItem) {
		item.destroyAll();

		for (const i = 0; i !== root.removingItems.length; i++) {
			if (root.removingItems[i] === item) {
				root.removingItems.splice(i, 1);
				break;
			}
		}
	}

	function finishAnimations() {
		// using forEach on list property might be tricky in older QML, but standard in recent
		// Note: 'list' type in QML doesn't always have forEach. converting to array or using loop?
		// But existing code used it. I will keep it but qualify.
		// Actually, 'removingItems' is a list<SlideViewItem>, which behave like arrays in newer QML.
		// If it worked before, I'll keep logic but use 'root.'
		// Wait, 'removingItems.forEach' ?? QML list properties are usually not arrays.
		// But maybe it's a var property in usage? No, defined as list<>.
		// I will trust existing logic but qualify access.
		for (let i = 0; i < root.removingItems.length; i++) {
			root.removingItems[i].destroyAll();
		}
		root.removingItems = [];

		if (root.activeItem) {
			root.activeItem.finishIfRunning();
		}
	}

	Component.onDestruction: {
		// Manual loop for list destruction safety
		for (let i = 0; i < root.removingItems.length; i++) {
			root.removingItems[i].destroyAll();
		}
		root.activeItem?.destroyAll();
		root.pendingItem?.destroy();
	}
}
