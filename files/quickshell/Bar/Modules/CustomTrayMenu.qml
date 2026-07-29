pragma ComponentBehavior: Bound
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Quickshell
import qs.Settings
import qs.Components
import "../../Helpers/Color.js" as Color
import "../../Helpers/Utils.js" as Utils
import "../../Helpers/MenuUtils.js" as MenuUtils

    PopupWindow {
        id: trayMenu
        implicitWidth: Theme.panelMenuWidth
        visible: false
        color: "transparent"

    readonly property int _searchBarH: Math.max(1, Math.round(Theme.panelMenuItemHeight * 0.85))
    readonly property int _searchBarImplicitH: _searchBarH + 8
    property QsMenuHandle menu
    property var anchorItem: null
    property real anchorX
    property real anchorY

    anchor.item: anchorItem ? anchorItem : null
    anchor.rect.x: anchorX
    anchor.rect.y: anchorY - Math.round(Theme.panelMenuAnchorYOffset * Theme.scale(Screen))

    // Recursively destroy all open submenus in delegate tree
    function destroySubmenusRecursively(item) {
        if (!item || !item.contentItem) return;
        var children = item.contentItem.children;
        for (var i = 0; i < children.length; ++i) {
            var child = children[i];
            if (child.subMenu) {
                child.subMenu.hideMenu();
                child.subMenu.destroy();
                child.subMenu = null;
            }
            if (child.contentItem) {
                destroySubmenusRecursively(child);
            }
        }
    }

    function showAt(item, x, y) {
        if (!item) { return; }
        anchorItem = item;
        anchorX = x;
        anchorY = y;
        visible = true;
        searchField.text = "";
        Qt.callLater(() => {
            trayMenu.anchor.updateAnchor();
            searchField.forceActiveFocus();
        })
    }

    function hideMenu() {
        visible = false; searchField.text = ""; destroySubmenusRecursively(listView);
    }


    Item {
        anchors.fill: parent;
        Keys.onEscapePressed: trayMenu.hideMenu();
    }

    QsMenuOpener { id: opener; menu: trayMenu.menu }
    // Submenu host component passed into delegates
    Component { id: submenuHostComp; SubmenuHost { submenuHostComponent: submenuHostComp } }


    Rectangle {
        id: bg;
        anchors.fill: parent;
        color: Theme.background;
        border.color: Color.withAlpha(Theme.accentPrimary, 0.3);
        border.width: Theme.uiBorderWidth;
        radius: Theme.panelMenuRadius;
        z: 0;

        ColumnLayout {
            anchors.fill: parent;
            anchors.margins: Theme.panelMenuPadding;
            spacing: Theme.panelMenuItemSpacing;

            // ── Search bar ──
            Rectangle {
                id: searchContainer;
                Layout.fillWidth: true;
                implicitHeight: trayMenu._searchBarImplicitH;
                radius: 3;
                color: Color.withAlpha(Theme.accentPrimary, 0.08);
                border.color: Color.withAlpha(Theme.accentPrimary, 0.2);
                border.width: 1;
                visible: rootMenuModel.count > 0;

                RowLayout {
                    id: searchRow;
                    anchors.fill: parent;
                    anchors.margins: 2;
                    spacing: 4;

                    MaterialIcon {
                        icon: "search";
                        size: Math.max(1, Math.round(trayMenu._searchBarH * 0.7));
                        color: Theme.textSecondary;
                        Layout.alignment: Qt.AlignVCenter;
                        Layout.preferredWidth: size;
                    }

                    TextInput {
                        id: searchField;
                        Layout.fillWidth: true;
                        implicitHeight: trayMenu._searchBarH;
                        color: Theme.textPrimary;
                        font.family: Theme.fontFamily;
                        font.pixelSize: Math.round(Theme.fontSizeSmall * 0.85);
                        verticalAlignment: TextInput.AlignVCenter;
                        clip: true;

                        Keys.forwardTo: [listView];
                        Keys.onEscapePressed: {
                            if (searchField.text.length > 0) {
                                searchField.text = "";
                            } else {
                                trayMenu.hideMenu();
                            }
                        }
                        Keys.onReturnPressed: {
                            if (listView.currentIndex >= 0 && listView.currentIndex < listView.count) {
                                var del = listView.currentItem;
                                if (del && del.entryItem && del.entryItem.entryData) {
                                    del.entryItem.entryData.triggered();
                                    trayMenu.visible = false;
                                }
                            }
                        }
                        onAccepted: {
                            if (listView.currentIndex >= 0 && listView.currentIndex < listView.count) {
                                var del = listView.currentItem;
                                if (del && del.entryItem && del.entryItem.entryData) {
                                    del.entryItem.entryData.triggered();
                                    trayMenu.visible = false;
                                }
                            }
                        }
                        onTextChanged: listView.currentIndex = 0;
                    }
                }
            }

            // ── Menu items ──
            ListView {
                id: listView;
                Layout.fillWidth: true;
                Layout.fillHeight: true;
                spacing: Theme.panelMenuItemSpacing;
                clip: true;

                keyNavigationEnabled: true;
                keyNavigationWraps: true;

                model: ScriptModel {
                    id: rootMenuModel;
                    values: {
                        var items = MenuUtils.unwindMenuChildren(opener);
                        var q = (searchField.text || "").toLowerCase().trim();
                        if (!q) return items;
                        return items.filter(function(item) {
                            var label = (item.text || item.label || item.title || "");
                            return label.toLowerCase().indexOf(q) !== -1;
                        });
                    }
                    onValuesChanged: listView.currentIndex = 0;
                }

                delegate: Item {
                    required property var modelData;
                    width: listView.width;
                    height: entryItem.height;
                    readonly property alias entryItem: entryItem;
                    DelegateEntry {
                        id: entryItem;
                        entryData: parent.modelData;
                        listViewRef: listView;
                        submenuHostComponent: submenuHostComp;
                        menuWindow: trayMenu;
                    }
                }
            }
        }
    }

    // Update implicitHeight based on search + list content
    readonly property int _pad2: Theme.panelMenuPadding * 2;
    readonly property int _srchH: searchContainer.visible ? (_searchBarImplicitH + Theme.panelMenuItemSpacing) : 0;
    implicitHeight: Utils.clamp(
        _pad2 + _srchH + listView.contentHeight + Theme.panelMenuHeightExtra,
        60,
        Math.max(60, listView.contentHeight + Theme.panelMenuHeightExtra + 80)
    );

    Component {
        id: subMenuComponent;
        SubmenuHost { submenuHostComponent: submenuHostComp }
    }

    
}
