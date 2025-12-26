pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs

ColumnLayout {
	id: root
	property alias menu: menuView.menu;
	property Item animatingItem: null;
	property bool animating: root.animatingItem !== null;

	signal close();
	signal submenuExpanded(item: var);

	QsMenuOpener { id: menuView }

	spacing: 0

	Repeater {
		id: menuRepeater
		model: menuView.children;

		Loader {
			id: menuLoader
			required property var modelData;

			property var item: Component {
				BoundComponent {
					id: itemComponent
					source: "MenuItem.qml"

					property var entry: menuLoader.modelData

					function onClose() {
						root.close()
					}

					function onExpandedChanged() {
						if (itemComponent.expanded) root.submenuExpanded(itemComponent);
					}

					function onAnimatingChanged() {
						if (itemComponent.animating) {
							root.animatingItem = itemComponent;
						} else if (root.animatingItem === itemComponent) {
							root.animatingItem = null;
						}
					}

					Connections {
						id: expandedConnection
						target: root

						function onSubmenuExpanded(expandedItem) {
							if (itemComponent !== expandedItem) itemComponent.expanded = false;
						}
					}
				}
			}

			property var separator: Component {
				Item {
					id: separatorItem
					implicitHeight: seprect.height + 6

					Rectangle {
						id: seprect

						anchors {
							verticalCenter: separatorItem.verticalCenter
							left: separatorItem.left
							right: separatorItem.right
						}

						color: ShellGlobals.colors.separator
						height: 1
					}
				}
			}

			sourceComponent: menuLoader.modelData.isSeparator ? separator : item
			Layout.fillWidth: true
		}
	}
}
