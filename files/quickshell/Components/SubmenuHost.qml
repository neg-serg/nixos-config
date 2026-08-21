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
    id: subMenu
    implicitWidth: Theme.panelSubmenuWidth
    visible: false
    color: "transparent"

    readonly property int _searchBarH: Math.max(1, Math.round(Theme.panelMenuItemHeight * 0.85))
    readonly property int _searchBarImplicitH: _searchBarH + 8
    required property var menu
    required property Component submenuHostComponent
    property var anchorItem: null
    property real anchorX
    property real anchorY
    anchor.item: anchorItem ? anchorItem : null
    anchor.rect.x: anchorX
    anchor.rect.y: anchorY - Math.round(Theme.panelMenuAnchorYOffset * Theme.scale(ScreenUtil.screen(subMenu)))

    function showAt(item, x, y) {
        if (!item) return;
        anchorItem = item;
        anchorX = x;
        anchorY = y;
        visible = true;
        searchField.text = "";
        Qt.callLater(() => {
            if (subMenu.anchor && subMenu.anchor.item) subMenu.anchor.updateAnchor();
            searchField.forceActiveFocus();
        });
    }
    function hideMenu() { visible = false; searchField.text = ""; }
    function containsMouse() { return subMenu.containsMouse }

    Item { anchors.fill: parent; Keys.onEscapePressed: subMenu.hideMenu() }

    QsMenuOpener { id: opener; menu: subMenu.menu }

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
                implicitHeight: subMenu._searchBarImplicitH
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
                        size: Math.max(1, Math.round(subMenu._searchBarH * 0.7))
                        color: Theme.textSecondary
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredWidth: size
                    }

                    TextInput {
                        id: searchField
                        Layout.fillWidth: true
                        Layout.preferredHeight: subMenu._searchBarH;
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
                                subMenu.hideMenu();
                            }
                        }
                        Keys.onReturnPressed: {
                            if (listView.currentIndex >= 0 && listView.currentIndex < listView.count) {
                                var del = listView.currentItem;
                                if (del && del.entryItem && del.entryItem.entryData) {
                                    del.entryItem.entryData.triggered();
                                    subMenu.visible = false;
                                }
                            }
                        }
                        onAccepted: {
                            if (listView.currentIndex >= 0 && listView.currentIndex < listView.count) {
                                var del = listView.currentItem;
                                if (del && del.entryItem && del.entryItem.entryData) {
                                    del.entryItem.entryData.triggered();
                                    subMenu.visible = false;
                                }
                            }
                        }
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
                        submenuHostComponent: subMenu.submenuHostComponent
                        menuWindow: subMenu
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
