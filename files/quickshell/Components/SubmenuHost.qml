import QtQuick
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

    // An xdg-popup only gets keyboard input when it asks for the popup grab:
    // without this the search field never saw a keystroke, the menu could not be
    // closed with Escape and the search looked dead (typing went to the focused
    // toplevel instead). grabFocus is only meaningful while the popup is mapped.
    grabFocus: visible

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

    // Identity of the tray app this menu belongs to, so a clicked entry can be
    // turned back into "the window of that app" (see TrayRaise). The root tray
    // menu is told which item was right-clicked in SystemTray; nested hosts
    // inherit the value through DelegateEntry's createObject().
    property var trayContext: null

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
        // The grab is granted asynchronously: forceActiveFocus() above may run
        // while the window is still inactive, so retry once it certainly is.
        focusRetry.restart();
    }
    Timer {
        id: focusRetry
        interval: 60
        repeat: false
        onTriggered: if (menuHost.visible) searchField.forceActiveFocus()
    }

    function hideMenu() {
        visible = false; searchField.text = "";
        if (destroySubmenusOnHide) destroySubmenusRecursively(listView);
    }
    function containsMouse() { return menuHost.containsMouse }

    // Every way of choosing an entry goes through here: it triggers the item and
    // then gives TrayRaise a chance to raise the window behind it (a Qt app
    // cannot do that itself on Wayland; see TrayRaise).
    function activateEntry(entryData) {
        if (!entryData) return;
        entryData.triggered();
        TrayRaise.raiseForEntry(entryData);
    }

    // Trigger the highlighted entry; shared by Return and search-bar accept.
    function activateCurrentItem() {
        if (listView.currentIndex >= 0 && listView.currentIndex < listView.count) {
            var del = listView.currentItem;
            if (del && del.entryItem && del.entryItem.entryData) {
                menuHost.activateEntry(del.entryItem.entryData);
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
                        trayContext: menuHost.trayContext
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
