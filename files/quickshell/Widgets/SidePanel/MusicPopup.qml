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
        // Fixed content height from settings. Do NOT derive it from the Music
        // widget's implicitHeight: that value is state-dependent (the metadata
        // column layout collapses between shows) and once it turned invalid the
        // card collapsed to a 1px sliver — the window mapped, nothing rendered.
        // The height is (re)assigned in showAt (JS, after the window maps) so
        // an early declarative evaluation seeing NaN cannot stick.
        property real musicHeightPx: Math.round(Settings.settings.musicPopupHeight * Theme.scale(Screen))
        property int contentPaddingPx: Math.round(Settings.settings.musicPopupPadding * Theme.scale(Screen))
        property real cardHeightPx: 300 // refreshed by showAt once the window maps
        function computeCardHeight() {
            try {
                const pad = Math.max(0, toast.contentPaddingPx) || 12;
                const mh = toast.musicHeightPx;
                if (!isFinite(mh) || mh <= 0) return 300;
                const floor = Math.round(pad + Math.max(120, mh * 0.5));
                const cap = Math.max(floor, Math.round(ScreenUtil.height(sidebarPopup) * 0.7));
                return Math.round(Utils.clamp(pad + mh, floor, cap));
            } catch (e) {
                return 300;
            }
        }

        // --- Fade in/out (explicit animations). Slide was dropped: a moving
        // card would require a mask region tracking the animation; the static
        // mask only describes the resting card. Explicit NumberAnimations are
        // used instead of a Behavior so a hide can never stall with the window
        // mapped but invisible (opacity stuck at 0): fadeOut always completes
        // and its onStopped closes the window.
        property bool _hiding: false
        property real _contentOpacity: 0
        NumberAnimation {
            id: fadeIn
            target: toast
            property: "_contentOpacity"
            from: 0
            to: 1
            duration: Theme.sidePanelPopupSlideMs
            easing.type: Theme.uiEasingRipple
        }
        NumberAnimation {
            id: fadeOut
            target: toast
            property: "_contentOpacity"
            duration: Theme.sidePanelPopupSlideMs
            easing.type: Theme.uiEasingRipple
            onStopped: {
                if (toast._hiding) {
                    toast.visible = false;
                    toast._hiding = false;
                    toast._contentOpacity = 0;
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
        // (qs-music layer spans 0..(screenH-barH)). anchorWindow.height must NOT
        // be added here (double-counts the bar); instead the card gets a small
        // breathing gap above the bar on top of the base edge margin.
        // Extra gap above the panel in scaled logical px (tune here).
        property real _bottomGapPx: Math.max(0, Math.round(6 * Theme.scale(Screen)))
        function computeBottomMargin() {
            return toast.baseMargin() + toast._bottomGapPx;
        }

        // --- Public control
        function showAt() {
            if (fadeOut.running) fadeOut.stop();
            toast._hiding = false;
            hideFallback.stop(); // a new show cancels the pending hide

            toast._marginRight = toast.baseMargin();
            toast._marginBottom = toast.computeBottomMargin();
            toast.cardHeightPx = toast.computeCardHeight(); // size before mapping

            if (!visible) {
                visible = true;
                _contentOpacity = 0;
            } else if (_contentOpacity <= 0.01) {
                _contentOpacity = 0; // self-heal a stale invisible window
            }
            // Animate from the current opacity so an interrupted fade never
            // jumps; fadeIn.to stays 1.
            fadeIn.from = Math.max(0, toast._contentOpacity);
            fadeIn.start();
            toast.startAutoHide();
            if (Settings.settings && Settings.settings.debugLogs) {
                console.debug("[qs-music] showAt card=" + cardBox.width + "x" + cardBox.height
                    + " mb=" + toast._marginBottom + " mr=" + toast._marginRight);
                // Re-check after layout settles (implicit sizes / bindings
                // may still be mid-flight at showAt time).
                Qt.callLater(function() {
                    console.debug("[qs-music] showAt+layout card=" + cardBox.width + "x" + cardBox.height
                        + " opacity=" + toast._contentOpacity.toFixed(2)
                        + " musicH=" + musicHeightPx + " pad=" + contentPaddingPx);
                });
            }
        }

        // Safety net: never leave the window mapped with a stuck fade-out.
        // If the fade-out animation is interrupted before it completes (so
        // fadeOut.onStopped never fires), force the window closed shortly after.
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
            if (fadeIn.running) fadeIn.stop();
            fadeOut.from = toast._contentOpacity;
            fadeOut.to = 0;
            fadeOut.start(); // onStopped closes the window
            hideFallback.start(); // safety net in case the animation is interrupted
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