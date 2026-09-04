import QtQuick 2.15
import QtQuick.Layouts 1.15
import Quickshell
import Quickshell.Wayland
import qs.Components
import qs.Settings
import "../../Helpers/Utils.js" as Utils
import "../../Helpers/ScreenUtil.js" as ScreenUtil

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

    // Music toast as a WlrLayershell window (compositor blur, hyprglass).
    // Mapping constraints in this Quickshell build (0.3.1 rev 2d3b3e9): a
    // surface appears only for full-height right/top/bottom anchors with
    // ExclusionMode.Normal, the default layer and NO WlrLayershell.margins.
    // The window is therefore full-height; the card is pinned to the
    // bottom-right corner by inner anchors, and the mask Region restricts
    // input to the card rect so the empty transparent strip never eats clicks.
    PanelWindow {
        id: toast
        color: "transparent"
        visible: false

        WlrLayershell.namespace: "qs-music"
        WlrLayershell.exclusionMode: ExclusionMode.Normal

        anchors.right: true
        anchors.top: true
        anchors.bottom: true

        // Card inset from the screen edges; consumed by the inner cardBox
        // anchors (margins on the window itself break mapping).
        property real _marginRight: 0
        property real _marginBottom: 0

        // Window width = card + right inset, so the card fits on screen
        // without WlrLayershell.margins.
        implicitWidth: Math.max(1, Math.round(toast.cardWidthPx + toast._marginRight))

        // Restrict pointer input to the card rect (window-local coords).
        // Clicks on the transparent full-height strip fall through to the
        // windows below, same trick as NotificationOverlay.
        mask: Region {
            x: cardBox.x
            y: cardBox.y
            width: cardBox.width
            height: cardBox.height
        }

        // --- Auto-hide with pause on hover/focus and while cursor is on panel
        property int autoHideTotalMs: Theme.sidePanelPopupAutoHideMs
        property int _autoHideRemainingMs: autoHideTotalMs
        property real _autoHideStartedAtMs: 0
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
        property real cardWidthPx: Math.round(Settings.settings.musicPopupWidth * Theme.scale(Screen))
        property real musicHeightPx: (musicWidget && musicWidget.implicitHeight > 0)
            ? Math.round(musicWidget.implicitHeight)
            : Math.round(Settings.settings.musicPopupHeight * Theme.scale(Screen))
        property int contentPaddingPx: Math.round(Settings.settings.musicPopupPadding * Theme.scale(Screen))
        // Card height = content + its top inset; clamped to 70% of the screen.
        property real cardHeightPx: Math.round(Utils.clamp(
            toast.contentPaddingPx + toast.musicHeightPx,
            1,
            Math.max(1, Math.round(ScreenUtil.height(sidebarPopup) * 0.7))))

        // --- Fade in/out. Slide was dropped: a moving card would require a
        // mask region tracking the animation; the static mask only describes
        // the resting card.
        property bool _hiding: false
        property real _contentOpacity: 0
        Behavior on _contentOpacity {
            NumberAnimation {
                id: contentFade
                duration: Theme.sidePanelPopupSlideMs
                easing.type: Theme.uiEasingRipple
                onStopped: {
                    if (toast._hiding && toast._contentOpacity <= 0.001) {
                        toast.visible = false;
                        toast._hiding = false;
                    }
                }
            }
        }

        // Keep anchor in sync with panel window changes (margin recalculation)
        Connections {
            target: sidebarPopup.anchorWindow
            ignoreUnknownSignals: true
            function onHeightChanged() {
                if (!toast.visible) return;
                toast._marginBottom = toast.computeBottomMargin();
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

        // Base edge margin around the card (right and bottom insets).
        function baseMargin() {
            const scale = Theme.scale(Screen);
            const cfgMargin = (Settings.settings && Settings.settings.musicPopupEdgeMargin !== undefined)
                              ? Settings.settings.musicPopupEdgeMargin
                              : Theme.sidePanelPopupOuterMargin;
            return Math.max(0, Math.round(cfgMargin * scale));
        }
        // Bottom inset for the card. The full-height window is bottom-anchored,
        // so WlrLayershell already ends it at the top of the bar's reserved zone
        // (qs-music layer spans 0..(screenH-barH)). Adding anchorWindow.height
        // again double-counts the bar and leaves a tall gap above it — observed
        // live as ~30px instead of the intended ~5px. anchorWindow is still used
        // for hover-pause of the auto-hide timer.
        function computeBottomMargin() {
            return toast.baseMargin();
        }

        // --- Public control
        function showAt() {
            if (toast._hiding) {
                toast._hiding = false;
                hideFallback.stop(); // a new show cancels the pending hide
            }

            toast._marginRight = toast.baseMargin();
            toast._marginBottom = toast.computeBottomMargin();

            if (!visible) {
                visible = true;
                _contentOpacity = 0; // start the fade from a clean slate
            }
            _contentOpacity = 1;
            toast.startAutoHide();
            if (Settings.settings && Settings.settings.debugLogs) {
                console.debug("[qs-music] showAt card=" + cardBox.width + "x" + cardBox.height
                    + " mb=" + toast._marginBottom + " mr=" + toast._marginRight);
            }
        }

        // Safety net: never leave the window mapped with a stuck fade-out.
        // If the Behavior animation is interrupted or already at 0 (so its
        // onStopped never fires), force the window closed shortly after.
        Timer {
            id: hideFallback
            interval: Math.max(Theme.sidePanelPopupSlideMs + 120, 350)
            repeat: false
            onTriggered: {
                if (toast._hiding && toast.visible) {
                    toast.visible = false;
                    toast._hiding = false;
                    toast._contentOpacity = 0;
                }
            }
        }

        function hidePopup() {
            if (!visible || _hiding) return;
            _hiding = true;
            _contentOpacity = 0; // contentFade hides the window when done
            hideFallback.start();
        }

        // --- Content
        // Card rect pinned to the bottom-right corner of the full-height window.
        Item {
            id: cardBox
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: toast._marginRight
            anchors.bottomMargin: toast._marginBottom
            width: toast.cardWidthPx
            height: toast.cardHeightPx
            opacity: toast._contentOpacity

            FocusScope {
                anchors.fill: parent

                // Pause auto-hide while pointer is over the card; resume on exit
                HoverHandler {
                    id: hover
                    onActiveChanged: {
                        if (active) toast.pauseAutoHide();
                        else toast.resumeAutoHide();
                    }
                }

                // Pause while a descendant has active focus (keyboard interaction)
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