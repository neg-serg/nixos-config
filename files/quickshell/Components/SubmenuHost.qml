import QtQuick
import QtQuick.Controls
import QtQuick.Layouts 1.15
import Quickshell
import qs.Components
import qs.Settings
import "../Helpers/Color.js" as Color
import "../Helpers/Utils.js" as Utils
import "../Helpers/MenuUtils.js" as MenuUtils
import "../Helpers/ScreenUtil.js" as ScreenUtil

PopupWindow {
    // Do not call this id `subMenu`: DelegateEntry declares a property of that name
    // (`property var subMenu: null`), and inside its body an unqualified `subMenu`
    // binds to that property instead of to this window. The delegate used to pass
    // `subMenu.submenuHostComponent` / `menuWindow: subMenu`, so both were null:
    // every menu entry ended up disabled (`enabled: … && menuWindow.visible`) and
    // nested submenus could not be created. Verified with a minimal Qt 6.11 repro.
    id: menuHost
    implicitWidth: Theme.panelSubmenuWidth
    visible: false
    color: "transparent"

    readonly property int _searchBarH: Math.max(1, Math.round(Theme.panelMenuItemHeight * 0.85))
    readonly property int _searchBarImplicitH: _searchBarH + 8
    // Not required: the root tray menu is created without a handle and gets it
    // assigned on right-click (SystemTray / NetClusterCapsule). Nested hosts
    // always pass one through DelegateEntry's createObject(). Default to null
    // rather than leave it undefined: QsMenuOpener below takes a QsMenuHandle*,
    // and an undefined value warns on every start.
    property var menu: null
    required property Component submenuHostComponent
    property var anchorItem: null
    property real anchorX
    property real anchorY
    anchor.item: anchorItem ? anchorItem : null
    anchor.rect.x: anchorX
    anchor.rect.y: anchorY - Math.round(Theme.panelMenuAnchorYOffset * Theme.scale(ScreenUtil.screen(menuHost)))

    // Only the root tray menu owns the whole submenu tree; a nested host is
    // torn down by its parent (see CustomTrayMenu), so it keeps the plain hide.
    property bool destroySubmenusOnHide: false

    // Recursively destroy all open submenus in delegate tree
    function destroySubmenusRecursively(item) {
        if (!item || !item.contentItem) return;
        // Iterate a snapshot and collect submenus first: destroying children
        // while iterating the live children list mutates the list being walked.
        var children = item.contentItem.children.slice();
        var submenus = [];
        for (var i = 0; i < children.length; ++i) {
            var child = children[i];
            if (child.subMenu) {
                submenus.push(child.subMenu);
                child.subMenu = null;
            }
            if (child.contentItem) {
                destroySubmenusRecursively(child);
            }
        }
        for (var j = 0; j < submenus.length; ++j) {
            submenus[j].hideMenu();
            submenus[j].destroy();
        }
    }

    function showAt(item, x, y) {
        if (!item) return;
        anchorItem = item;
        anchorX = x;
        anchorY = y;
        visible = true;
        searchField.text = "";
        Qt.callLater(() => {
            if (menuHost.anchor && menuHost.anchor.item) menuHost.anchor.updateAnchor();
            searchField.forceActiveFocus();
        });
    }
    function hideMenu() {
        visible = false; searchField.text = "";
        if (destroySubmenusOnHide) destroySubmenusRecursively(listView);
    }
    function containsMouse() { return menuHost.containsMouse }

    // Trigger the highlighted entry; shared by Return and search-bar accept.
    function activateCurrentItem() {
        if (listView.currentIndex >= 0 && listView.currentIndex < listView.count) {
            var del = listView.currentItem;
            if (del && del.entryItem && del.entryItem.entryData) {
                del.entryItem.entryData.triggered();
                menuHost.visible = false;
            }
        }
    }

    Item { anchors.fill: parent; Keys.onEscapePressed: menuHost.hideMenu() }

    QsMenuOpener { id: opener; menu: menuHost.menu }

    Rectangle {
        id: bg
        anchors.fill: parent
        color: Theme.background
        border.color: Color.withAlpha(Theme.accentPrimary, 0.3);
        border.width: Theme.uiBorderWidth
        radius: Theme.panelMenuRadius
        z: 0

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.panelMenuPadding
            spacing: Theme.panelMenuItemSpacing

            // ── Search bar ──
            Rectangle {
                id: searchContainer
                Layout.fillWidth: true
                implicitHeight: menuHost._searchBarImplicitH
                radius: 3
                color: Color.withAlpha(Theme.accentPrimary, 0.08)
                border.color: Color.withAlpha(Theme.accentPrimary, 0.2)
                border.width: 1
                visible: subMenuModel.count > 0

                RowLayout {
                    id: searchRow
                    anchors.fill: parent
                    anchors.margins: 2
                    spacing: 4

                    MaterialIcon {
                        icon: "search"
                        size: Math.max(1, Math.round(menuHost._searchBarH * 0.7))
                        color: Theme.textSecondary
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredWidth: size
                    }

                    TextInput {
                        id: searchField
                        Layout.fillWidth: true
                        Layout.preferredHeight: menuHost._searchBarH;
                        color: Theme.textPrimary
                        font.family: Theme.fontFamily
                        font.pixelSize: Math.round(Theme.fontSizeSmall * 0.85)
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true

                        Keys.forwardTo: [listView]
                        Keys.onEscapePressed: {
                            if (searchField.text.length > 0) {
                                searchField.text = "";
                            } else {
                                menuHost.hideMenu();
                            }
                        }
                        Keys.onReturnPressed: menuHost.activateCurrentItem()
                        onAccepted: menuHost.activateCurrentItem()
                        onTextChanged: if (listView.currentIndex !== 0) listView.currentIndex = 0
                    }
                }
            }

            // ── Menu items ──
            ListView {
                id: listView
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Theme.panelMenuItemSpacing
                clip: true

                keyNavigationEnabled: true
                keyNavigationWraps: true

                model: ScriptModel {
                    id: subMenuModel
                    values: {
                        var items = MenuUtils.unwindMenuChildren(opener);
                        var q = (searchField.text || "").toLowerCase().trim();
                        if (!q) return items;
                        return items.filter(function(item) {
                            var label = (item.text || item.label || item.title || "");
                            return label.toLowerCase().indexOf(q) !== -1;
                        });
                    }
                    onValuesChanged: if (listView.currentIndex !== 0) listView.currentIndex = 0
                }

                delegate: Item {
                    required property var modelData
                    width: listView.width
                    height: entryItem.height
                    readonly property alias entryItem: entryItem
                    DelegateEntry {
                        id: entryItem
                        entryData: parent.modelData
                        listViewRef: listView
                        submenuHostComponent: menuHost.submenuHostComponent
                        menuWindow: menuHost
                    }
                }
            }
        }
    }

    // Update implicitHeight based on search + list content
    readonly property int _pad2: Theme.panelMenuPadding * 2
    readonly property int _srchH: searchContainer.visible ? (_searchBarImplicitH + Theme.panelMenuItemSpacing) : 0
    implicitHeight: Utils.clamp(
        _pad2 + _srchH + listView.contentHeight + Theme.panelMenuHeightExtra,
        60,
        Math.max(60, listView.contentHeight + Theme.panelMenuHeightExtra + 80)
    );
}
