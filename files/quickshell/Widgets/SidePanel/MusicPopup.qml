import QtQuick 2.15
import QtQuick.Layouts 1.15
import Quickshell
import Quickshell.Wayland
import qs.Components
import qs.Settings
import "../../Helpers/Utils.js" as Utils

Item {
    id: sidebarPopup
    // Reflect window visibility for external checks (buttons, etc.)
    visible: toast.visible

    // Anchor: panel/bar window for margin calculation
    property var anchorWindow: null
    // Panel edge: "top" | "bottom" | "left" | "right"
    property string panelEdge: "bottom"

    // Public API
    function showAt()   { toast.showAt(); }
    function hidePopup(){ toast.hidePopup(); }

    // ── Music popup as WlrLayershell window for compositor blur (hyprglass) ──
    Window {
        id: toast
        color: "transparent"
        visible: false

        WlrLayershell.namespace: "qs-music"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusionMode: ExclusionMode.Ignore

        // Position: right edge, above the bottom panel
        anchors.right: true
        anchors.bottom: true

        // Dynamic margins set in showAt() based on panel height and edge margin
        property real _marginRight: 0
        property real _marginBottom: 0
        margins.right: toast._marginRight
        margins.bottom: toast._marginBottom

        // --- Auto-hide with pause on hover/focus and while cursor is on panel
        property int autoHideTotalMs: Theme.sidePanelPopupAutoHideMs
        property int _autoHideRemainingMs: autoHideTotalMs
        property double _autoHideStartedAtMs: 0
        Timer {
            id: autoHideTimer
            interval: toast._autoHideRemainingMs
            repeat: false
            onTriggered: {
                if (!toast._hiding && toast.visible) {
                    // Do not hide if cursor is currently on the panel
                    if (!(sidebarPopup.anchorWindow && sidebarPopup.anchorWindow.panelHovering === true)) {
                        toast.hidePopup();
                    } else {
                        // Stay armed to resume when cursor leaves the panel
                        toast.pauseAutoHide();
                    }
                }
            }
        }
        function startAutoHide(ms) {
            toast._autoHideRemainingMs = (ms !== undefined && ms !== null) ? ms : toast.autoHideTotalMs;
            toast._autoHideStartedAtMs = Date.now();
            autoHideTimer.interval = toast._autoHideRemainingMs;
            autoHideTimer.restart();
        }
        function pauseAutoHide() {
            if (!autoHideTimer.running) return;
            const elapsed = Utils.clamp(Date.now() - toast._autoHideStartedAtMs, 0, 3600000);
            toast._autoHideRemainingMs = Utils.clamp(toast._autoHideRemainingMs - elapsed, 0, 3600000);
            autoHideTimer.stop();
        }
        function resumeAutoHide() {
            if (toast._autoHideRemainingMs <= 0) { toast.hidePopup(); return; }
            toast._autoHideStartedAtMs = Date.now();
            autoHideTimer.interval = toast._autoHideRemainingMs;
            autoHideTimer.restart();
        }
        function cancelAutoHide() {
            autoHideTimer.stop();
            toast._autoHideRemainingMs = toast.autoHideTotalMs;
        }
        onVisibleChanged: {
            if (visible) {
                toast.startAutoHide();
                if (sidebarPopup.anchorWindow && sidebarPopup.anchorWindow.panelHovering === true) {
                    toast.pauseAutoHide();
                }
            } else {
                toast.cancelAutoHide();
            }
        }

        // --- Sizing (scaled by per-screen factor)
        property real computedHeightPx: -1
        property real musicWidthPx: Math.round(Settings.settings.musicPopupWidth * Theme.scale(Screen))
        property real musicHeightPx: (musicWidget && musicWidget.implicitHeight > 0)
            ? Math.round(musicWidget.implicitHeight)
            : Math.round(Settings.settings.musicPopupHeight * Theme.scale(Screen))
        property int contentPaddingPx:Math.round(Settings.settings.musicPopupPadding * Theme.scale(Screen))

        width: Math.round(musicWidthPx)
        height: Math.round((computedHeightPx >= 0) ? computedHeightPx : musicHeightPx)

        // --- Slide animation (animate inner content, not the window)
        property bool _hiding: false
        property real slideX: 0
        NumberFadeBehavior {
            id: slide
            target: toast
            property: "slideX"
            duration: Theme.sidePanelPopupSlideMs
            easing.type: Theme.uiEasingRipple
            onStopped: {
                if (toast._hiding) {
                    toast.visible = false;
                    toast._hiding = false;
                }
            }
        }

        // Keep anchor in sync with panel window changes (for margin recalculation)
        Connections {
            target: sidebarPopup.anchorWindow
            ignoreUnknownSignals: true
            function onHeightChanged() {
                if (!toast.visible) return;
                const scale = Theme.scale(Screen);
                const cfgMargin = (Settings.settings && Settings.settings.musicPopupEdgeMargin !== undefined)
                                  ? Settings.settings.musicPopupEdgeMargin
                                  : Theme.sidePanelPopupOuterMargin;
                const baseMargin = Math.max(0, Math.round(cfgMargin * scale));
                if (sidebarPopup.panelEdge === "bottom") {
                    toast._marginBottom = (sidebarPopup.anchorWindow ? sidebarPopup.anchorWindow.height : 0) + baseMargin;
                }
            }
            function onPanelHoveringChanged() {
                if (!sidebarPopup.anchorWindow) return;
                if (sidebarPopup.anchorWindow.panelHovering) toast.pauseAutoHide();
                else toast.resumeAutoHide();
            }
        }
        Connections {
            target: Settings.settings
            ignoreUnknownSignals: true
            function onMusicPopupEdgeMarginChanged() {
                if (toast.visible) toast.showAt(); // reposition
            }
        }

        // --- Public control
        function showAt() {
            const scale = Theme.scale(Screen);
            const cfgMargin = (Settings.settings && Settings.settings.musicPopupEdgeMargin !== undefined)
                              ? Settings.settings.musicPopupEdgeMargin
                              : Theme.sidePanelPopupOuterMargin;
            const baseMargin = Math.max(0, Math.round(cfgMargin * scale));

            if (computedHeightPx < 0) {
                var ih = (musicWidget && musicWidget.implicitHeight > 0)
                         ? musicWidget.implicitHeight
                         : (Settings.settings.musicPopupHeight * scale);
                const guardMax = Utils.clamp(Math.round(Screen.height * 0.7), 1, Screen.height);
                computedHeightPx = Utils.clamp(Math.round(ih), 1, guardMax);
            }

            // Set WlrLayershell margins for positioning: right edge + above panel
            toast._marginRight = baseMargin;
            if (sidebarPopup.panelEdge === "bottom") {
                toast._marginBottom = (sidebarPopup.anchorWindow ? sidebarPopup.anchorWindow.height : 0) + baseMargin;
            } else {
                toast._marginBottom = baseMargin;
            }

            if (!visible) {
                visible = true;
                slideX = toast.width; // start fully to the right
            }
            slide.stop();
            _hiding = false;
            slide.from = slideX;
            slide.to   = 0;
            slide.start();
        }

        function hidePopup() {
            slide.stop();
            _hiding = true;
            slide.from = slideX;
            slide.to   = toast.width;
            slide.start();
        }

        // --- Content
        // Slide container for both background and content
        Item {
            id: contentRoot
            anchors.fill: parent
            transform: Translate { x: toast.slideX }

            FocusScope {
                anchors.fill: parent

            // Pause auto-hide while pointer is over popup; resume on exit
            HoverHandler {
                id: hover
                onActiveChanged: {
                    if (active) toast.pauseAutoHide();
                    else toast.resumeAutoHide();
                }
            }

            // Pause while any descendant within this scope has active focus (keyboard interaction)
            onActiveFocusChanged: {
                if (activeFocus) toast.pauseAutoHide();
                else toast.resumeAutoHide();
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.leftMargin: toast.contentPaddingPx
                anchors.rightMargin: 0
                anchors.topMargin: toast.contentPaddingPx
                spacing: Theme.sidePanelPopupSpacing

                RowLayout {
                    spacing: Math.round(Theme.sidePanelSpacingMedium * Theme.scale(Screen))
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignRight

                    Music {
                        id: musicWidget
                        height: toast.musicHeightPx
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignRight
                    }
                }
            }
            }
        }
    }
}
