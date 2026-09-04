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
        property real musicHeightPx: Math.round(Settings.settings.musicPopupHeight
            * ((toast.cardWidthPx > 0 ? toast.cardWidthPx : Settings.settings.musicPopupWidth)
               / Settings.settings.musicPopupWidth))
        property int contentPaddingPx: Math.round(Settings.settings.musicPopupPadding
            * ((toast.cardWidthPx > 0 ? toast.cardWidthPx : Settings.settings.musicPopupWidth)
               / Settings.settings.musicPopupWidth))
        property real cardHeightPx: 300 // refreshed by showAt once the window maps
        function computeCardHeight() {
            try {
                // Derive the scale from the WORKING card width (Theme.scale(Screen)
                // can be a transient value before the window maps — using it
                // directly produced a too-short card that left the toast invisible
                // or made it jump size).
                const wScale = (toast.cardWidthPx > 0 && Settings.settings.musicPopupWidth > 0)
                    ? toast.cardWidthPx / Settings.settings.musicPopupWidth : 1.15;
                const pad = Math.max(0, Math.round(Settings.settings.musicPopupPadding * wScale)) || 12;
                const mh = Math.round(Settings.settings.musicPopupHeight * wScale);
                if (!isFinite(mh) || mh <= 0) mh = 300;
                const floor = Math.round(pad + Math.max(120, mh * 0.5));
                const cap = Math.max(floor, Math.round(ScreenUtil.height(sidebarPopup) * 0.7));
                return Math.round(Utils.clamp(pad + mh, floor, cap));
            } catch (e) {
                return 300;
            }
        }

        // --- Appearance: slow, gentle fade. Animate the card Box's opacity
        // directly (an Item opacity animates reliably), NOT a custom property on
        // the just-mapped layer window (that flickered/stalled). Fade runs only
        // on the hidden→shown transition so rapid re-shows never blink it.
        property bool _hiding: false
        property int _fadeInMs: 500
        property int _fadeOutMs: 350
        NumberAnimation {
            id: fadeIn
            target: cardBox
            property: "opacity"
            duration: toast._fadeInMs
            easing.type: Theme.uiEasingRipple
        }
        NumberAnimation {
            id: fadeOut
            target: cardBox
            property: "opacity"
            duration: toast._fadeOutMs
            easing.type: Theme.uiEasingRipple
            onStopped: {
                if (toast._hiding) {
                    toast.visible = false;
                    toast._hiding = false;
                    cardBox.opacity = 1;
                }
            }
        }
        Timer {
            id: hideFallback
            interval: toast._fadeOutMs + 150
            repeat: false
            onTriggered: {
                if (toast._hiding && toast.visible) {
                    toast.visible = false;
                    toast._hiding = false;
                    cardBox.opacity = 1;
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
        // be added here (double-counts the bar); instead the card floats a clear
        // distance above the bar on top of the base edge margin (~64 scaled px
        // of extra air, well clear of the panel).
        // Extra gap above the panel in scaled logical px (tune here).
        property real _bottomGapPx: Math.max(0, Math.round(56 * Theme.scale(Screen)))
        function computeBottomMargin() {
            return toast.baseMargin() + toast._bottomGapPx;
        }

        // --- Public control
        function showAt() {
            toast._hiding = false;
            hideFallback.stop();
            toast._marginRight = toast.baseMargin();
            toast._marginBottom = toast.computeBottomMargin();
            toast.cardHeightPx = toast.computeCardHeight(); // size before mapping
            if (!toast.visible) {
                toast.visible = true;
                cardBox.opacity = 0;
                fadeIn.from = 0;
                fadeIn.start(); // slow fade-in
            } else {
                // Already visible: never restart the fade (would blink).
                if (fadeOut.running) fadeOut.stop();
                cardBox.opacity = 1;
            }
            toast.startAutoHide();
            if (Settings.settings && Settings.settings.debugLogs) {
                console.debug("[qs-music] showAt card=" + cardBox.width + "x" + cardBox.height
                    + " mb=" + toast._marginBottom + " mr=" + toast._marginRight);
                Qt.callLater(function() {
                    console.debug("[qs-music] showAt+layout card=" + cardBox.width + "x" + cardBox.height
                        + " opacity=" + cardBox.opacity.toFixed(2)
                        + " musicH=" + musicHeightPx + " pad=" + contentPaddingPx);
                });
            }
        }

        function hidePopup() {
            if (!visible || _hiding) return;
            _hiding = true;
            fadeIn.stop();
            fadeOut.from = cardBox.opacity;
            fadeOut.to = 0;
            fadeOut.start(); // onStopped/fallback close the window
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
            // opacity is driven by fadeIn/fadeOut (Item opacity, reliable).

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