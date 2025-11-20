import QtQuick
import QtQuick.Layouts
import Quickshell
import QtQuick.Effects
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import qs.Settings
import qs.Components
import "../../Helpers/TooltipText.js" as TooltipText
import qs.Services as Services
import "../../Helpers/CapsuleMetrics.js" as CapsuleMetrics

Row {
    id: root
    property bool panelHover: false
    property bool hotHover: false
    property bool holdOpen: false
    property bool shortHoldActive: false

    // Timers centralized in TrayController service
    Connections {
        target: Services.TrayController
        function onLongHold() { root.holdOpen = false; root.expanded = false }
        function onShortHold() { root.shortHoldActive = false; if (!root.panelHover && !root.hotHover && !root.holdOpen) root.expanded = false }
        function onCollapseDelay() { root.expanded = false }
        function onGuardOff() { root.openGuard = false }
    }

    onHotHoverChanged: {
        if (hotHover) {
            Services.TrayController.stopShortHold();
            shortHoldActive = false;
            expanded = true;
        } else {
            const menuOpen = trayMenu && trayMenu.visible;
            if (!panelHover && !menuOpen && !holdOpen) {
                shortHoldActive = true;
                Services.TrayController.startShortHold();
            }
        }
    }
    property var shell
    property var screen
    property var trayMenu
    // Collapse delay handled by TrayController service
    function dismissOverlayNow(reason = "programmatic") { trayOverlay.close(reason); }
    readonly property real _scale: Theme.scale(root.screen || Screen)
    readonly property var capsuleMetrics: CapsuleMetrics.metrics(Theme, _scale)
    readonly property int capsuleInnerSize: capsuleMetrics.inner
    readonly property int panelHeightPx: Math.max(1, Math.round(Theme.panelHeight * _scale))
    readonly property int inlinePaddingPx: Math.max(2, Math.round(Theme.panelTrayInlinePadding * _scale))
    readonly property int trayIconSlot: Math.max(capsuleInnerSize, panelHeightPx)
    readonly property int trayIconInset: Math.max(1, Math.round(trayIconSlot * 0.08))
    readonly property int trayIconFrame: Math.max(8, trayIconSlot - trayIconInset * 2)
    readonly property int trayIconSize: Math.max(8, trayIconFrame - Math.round(trayIconInset * 0.5))
    readonly property bool tightSpacing: Settings.settings.systemTrayTightSpacing !== false
    spacing: Math.max(2, Math.round(Theme.panelRowSpacing * _scale * 0.5))
    Layout.alignment: Qt.AlignVCenter
    readonly property int capsuleHeight: trayIconSlot
    height: capsuleHeight
    Layout.preferredHeight: capsuleHeight

    property bool containsMouse: false
    property var systemTray: SystemTray

    property bool collapsed: Settings.settings.collapseSystemTray
    property bool expanded: false
    property bool openGuard: false
    // Inline tray background/border colors (overridable by parent capsule)
    property color inlineBgColor: Theme.background
    property color inlineBorderColor: Theme.borderSubtle

    OverlayToggleCapsule {
        id: trayOverlay
        capsuleVisible: false
        autoToggleOnTap: false
        screen: root.screen
        showOverlay: false
        overlayColor: showOverlay ? Theme.overlayStrong : "transparent"
        onDismissed: reason => {
            if (trayMenu && trayMenu.visible) trayMenu.hideMenu();
            if (!root.expanded) return;
            if (root.holdOpen || root.hotHover || root.panelHover || (trayMenu && trayMenu.visible)) return;
            if (reason === "programmatic") {
                Services.TrayController.stopCollapseDelay();
                root.expanded = false;
            } else {
                Services.TrayController.startCollapseDelay();
            }
        }
    }

    // Inline expanded content that participates in Row layout (shifts neighbors)
    Item {
        id: inlineBox
        visible: expanded
        anchors.verticalCenter: parent.verticalCenter
        readonly property int inlinePadding: tightSpacing ? 0 : Math.max(2, root.inlinePaddingPx)
        width: collapsedRow.implicitWidth + inlinePadding
        height: collapsedRow.implicitHeight + inlinePadding

        InlineTrayCapsule {
            id: inlineCapsule
            anchors.fill: parent
            inlineBackground: inlineBgColor
            inlineBorder: inlineBorderColor
            inlinePaddingScale: tightSpacing ? 0 : inlineCapsule.paddingScaleFor(root.inlinePaddingPx)
            inlineVerticalPaddingScale: inlineCapsule.paddingScaleFor(Math.max(2, root.inlinePaddingPx * 0.8))
            borderWidthOverride: 0
            borderVisible: false
            forceHeightFromMetrics: false
        }

        // Hover area over the inline box to keep it open while cursor is inside
        MouseArea {
            id: inlineHoverArea
            anchors.fill: inlineCapsule
            z: 999
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            onEntered: expanded = true
            onExited: {
                if (!root.panelHover && !root.hotHover && !root.holdOpen && !root.shortHoldActive) expanded = false
            }
        }
        Row {
            id: collapsedRow
            // Align to the right edge so reveal expands leftwards
            anchors.right: parent.right
            anchors.rightMargin: inlineBox.inlinePadding / 2
            anchors.verticalCenter: parent.verticalCenter
            spacing: Math.round(Theme.panelRowSpacingSmall * root._scale)
            Repeater {
                model: systemTray.items
                delegate: Item {
                    width: trayIconSlot
                    height: trayIconSlot
                    visible: modelData
                    // No per-icon animation; show immediately
                    opacity: 1
                    x: 0
                    Rectangle {
                        anchors.centerIn: parent
                        width: trayIconFrame
                        height: trayIconFrame
                        radius: Theme.cornerRadiusSmall
                        // Keep idle background opaque to avoid transparency halo; hover still uses overlay tint
                        color: trayItemMouseArea.containsMouse ? Theme.overlayWeak : Theme.surfaceHover
                        border.width: 0
                        border.color: "transparent"
                        clip: true
                        TrayIcon {
                            id: icon
                            anchors.centerIn: parent
                            size: trayIconSize
                            source: modelData?.icon || ""
                            grayscale: trayOverlay.expanded
                            opacity: ready ? 1 : 0
                        }
                    }
                    MouseArea {
                        id: trayItemMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                        onClicked: mouse => {
                            if (!modelData) return;
                            if (mouse.button === Qt.LeftButton) {
                                if (trayMenu && trayMenu.visible) trayMenu.hideMenu();
                                if (!modelData.onlyMenu) modelData.activate();
                                expanded = false;
                                root.dismissOverlayNow();
                            } else if (mouse.button === Qt.MiddleButton) {
                                if (trayMenu && trayMenu.visible) trayMenu.hideMenu();
                                modelData.secondaryActivate && modelData.secondaryActivate();
                                expanded = false;
                                root.dismissOverlayNow();
                            } else if (mouse.button === Qt.RightButton) {
                                if (trayMenu && trayMenu.visible) { trayMenu.hideMenu(); root.dismissOverlayNow(); return; }
                                if (modelData.hasMenu && modelData.menu && trayMenu) {
                                    const menuX = (width / 2) - (trayMenu.width / 2);
                                    const menuY = height + Math.round(Services.TrayController.menuYOffset * root._scale);
                                    trayMenu.menu = modelData.menu;
                                    trayMenu.showAt(parent, menuX, menuY);
                                    trayOverlay.open("tray-menu");
                                    try { trayOverlay.showOverlay = true; } catch (e) {}
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Collapsed trigger button (placed after inline box)
    PanelIconButton {
        id: collapsedButton
        z: 1002
        visible: false // hidden; tray reveals by hover in bottom-right hot zone
        anchors.verticalCenter: parent.verticalCenter
        size: Math.round(Theme.panelIconSize * root._scale)
        icon: Settings.settings.collapsedTrayIcon || "expand_more"
        iconRotation: expanded ? 90 : 0
        onClicked: {
            expanded = !expanded;
            if (expanded) { openGuard = true; Services.TrayController.startGuard(); }
            if (expanded) { trayOverlay.open("tray-expanded"); try { trayOverlay.showOverlay = false; } catch (e) {} }
            else root.dismissOverlayNow();
        }
    }

    onExpandedChanged: {
        if (!expanded) {
            if (trayMenu && trayMenu.visible) trayMenu.hideMenu();
            root.dismissOverlayNow();
        }
    }

    Connections {
        target: trayMenu
        function onVisibleChanged() {
            if (!trayMenu) return;
            if (trayMenu.visible) {
                root.expanded = true;
                root.holdOpen = true;
                Services.TrayController.stopLongHold();
                Services.TrayController.stopShortHold();
                root.shortHoldActive = false;
            } else {
                root.holdOpen = true;
                Services.TrayController.startLongHold();
            }
        }
    }


    // Inline icons (disabled: we show tray only via hover hot zone)
    Repeater {
        // Disabled always to avoid duplicate inline tray; use inlineBox above
        model: 0
        delegate: Item {
            width: Math.round(Theme.panelIconSize * root._scale)
            height: Math.round(Theme.panelIconSize * root._scale)

            visible: modelData
            property bool isHovered: trayMouseArea.containsMouse

            // No animations - static display

                    Rectangle {
                        anchors.centerIn: parent
                        width: Math.round(Theme.panelIconSizeSmall * root._scale)
                        height: Math.round(Theme.panelIconSizeSmall * root._scale)
                        radius: Theme.cornerRadiusSmall
                        color: "transparent"
                        clip: true

                        TrayIcon {
                            id: trayIcon
                            anchors.centerIn: parent
                            size: Math.round(Theme.panelIconSizeSmall * root._scale)
                            source: modelData?.icon || ""
                            grayscale: trayOverlay.expanded
                            opacity: ready ? 1 : 0
                        }
                    }

            MouseArea {
                id: trayMouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                onClicked: mouse => {
                    if (!modelData)
                        return;

                    if (mouse.button === Qt.LeftButton) {
                        // Close any open menu first
                        if (trayMenu && trayMenu.visible) {
                            trayMenu.hideMenu();
                        }

                        if (!modelData.onlyMenu) {
                            modelData.activate();
                        }
                    } else if (mouse.button === Qt.MiddleButton) {
                        // Close any open menu first
                        if (trayMenu && trayMenu.visible) {
                            trayMenu.hideMenu();
                        }

                        modelData.secondaryActivate && modelData.secondaryActivate();
                    } else if (mouse.button === Qt.RightButton) {
                        trayTooltip.visibleWhen = false;
                        // If menu is already visible, close it
                        if (trayMenu && trayMenu.visible) {
                            trayMenu.hideMenu();
                            trayOverlay.close("programmatic");
                            return;
                        }

                        if (modelData.hasMenu && modelData.menu && trayMenu) {
                            // Anchor the menu to the tray icon item (parent) and position it below the icon
                            const menuX = (width / 2) - (trayMenu.width / 2);
                            const menuY = height + Math.round(Services.TrayController.menuYOffset * root._scale);
                            trayMenu.menu = modelData.menu;
                            trayMenu.showAt(parent, menuX, menuY);
                            trayOverlay.open("tray-menu");
                            try { trayOverlay.showOverlay = false; } catch (e) {}
                        } else
                        
                        {}
                    }
                }
                onEntered: trayTooltip.visibleWhen = true
                onExited: trayTooltip.visibleWhen = false
            }

            PanelTooltip {
                id: trayTooltip
                text: TooltipText.compose(
                    modelData.tooltipTitle || modelData.name || modelData.id || "Tray Item",
                    "",
                    []
                )
                targetItem: trayIcon
                delayMs: Services.TrayController.tooltipDelayMs
                visibleWhen: false
            }

            Component.onDestruction:
            // No cache cleanup needed
            {}
        }
    }
}
