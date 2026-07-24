import QtQuick 2.15
import Quickshell
import Quickshell.Wayland
import qs.Components
import qs.Settings
import "../Helpers/Utils.js" as Utils

// Base class for semi-transparent overlay popups (calendar, music, monitor).
// Provides: WlrLayershell window, slide-in animation, auto-hide with hover pause.
PanelWindow {
    id: overlay

    color: "transparent"
    visible: false

    // ── Must be set by subclass ──
    property string popupNamespace: ""
    property var anchorWindow: null
    property string panelEdge: "bottom"

    // ── Slide animation ──
    property bool _hiding: false
    property real slideX: 0
    NumberFadeBehavior {
        id: slide
        target: overlay
        property: "slideX"
        duration: Theme.sidePanelPopupSlideMs
        easing.type: Theme.uiEasingRipple
        onStopped: {
            if (overlay._hiding) {
                overlay.visible = false
                overlay._hiding = false
            }
        }
    }

    // ── Positioning margins ──
    property real _marginRight: 0
    property real _marginBottom: 0
    WlrLayershell.namespace: popupNamespace
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.margins {
        right: overlay._marginRight
        bottom: overlay._marginBottom
    }

    anchors.right: true
    anchors.bottom: true

    // ── Auto-hide ──
    property int autoHideMs: Theme.sidePanelPopupAutoHideMs
    property int _autoHideRemainingMs: autoHideMs
    property real _autoHideStartedAtMs: 0
    Timer {
        id: autoHideTimer
        interval: overlay._autoHideRemainingMs
        repeat: false
        onTriggered: {
            if (!overlay._hiding && overlay.visible) {
                if (!(overlay.anchorWindow && overlay.anchorWindow.panelHovering === true))
                    overlay.hidePopup()
                else
                    overlay.pauseAutoHide()
            }
        }
    }

    function startAutoHide(ms) {
        overlay._autoHideRemainingMs = (ms !== undefined && ms !== null) ? ms : overlay.autoHideMs
        overlay._autoHideStartedAtMs = Date.now()
        autoHideTimer.interval = overlay._autoHideRemainingMs
        autoHideTimer.restart()
    }
    function pauseAutoHide() {
        if (!autoHideTimer.running) return
        var elapsed = Utils.clamp(Date.now() - overlay._autoHideStartedAtMs, 0, 3600000)
        overlay._autoHideRemainingMs = Utils.clamp(overlay._autoHideRemainingMs - elapsed, 0, 3600000)
        autoHideTimer.stop()
    }
    function resumeAutoHide() {
        if (overlay._autoHideRemainingMs <= 0) { overlay.hidePopup(); return }
        overlay._autoHideStartedAtMs = Date.now()
        autoHideTimer.interval = overlay._autoHideRemainingMs
        autoHideTimer.restart()
    }
    function cancelAutoHide() {
        autoHideTimer.stop()
        overlay._autoHideRemainingMs = overlay.autoHideMs
    }
    onVisibleChanged: {
        if (visible) {
            overlay.startAutoHide()
            if (overlay.anchorWindow && overlay.anchorWindow.panelHovering === true)
                overlay.pauseAutoHide()
        } else {
            overlay.cancelAutoHide()
        }
    }

    // ── Panel sync ──
    Connections {
        target: overlay.anchorWindow
        ignoreUnknownSignals: true
        function onHeightChanged() {
            if (!overlay.visible) return
            overlay._recalcMargins()
        }
        function onPanelHoveringChanged() {
            if (!overlay.anchorWindow) return
            if (overlay.anchorWindow.panelHovering) overlay.pauseAutoHide()
            else overlay.resumeAutoHide()
        }
    }

    // ── Public API ──
    property real popupWidth: 400
    property real popupHeight: 600
    property real edgeMargin: Theme.sidePanelPopupOuterMargin

    function _recalcMargins() {
        var scale = Theme.scale(Screen)
        var baseMargin = Math.max(0, Math.round(edgeMargin * scale))
        overlay._marginRight = baseMargin
        if (overlay.panelEdge === "bottom")
            overlay._marginBottom = (overlay.anchorWindow ? overlay.anchorWindow.height : 0) + baseMargin
        else
            overlay._marginBottom = baseMargin
    }

    function showAt() {
        overlay._recalcMargins()
        if (!visible) {
            visible = true
            slideX = overlay.width  // start off-screen to the right
        }
        slide.stop()
        overlay._hiding = false
        slide.from = slideX
        slide.to = 0
        slide.start()
    }

    function hidePopup() {
        slide.stop()
        overlay._hiding = true
        slide.from = slideX
        slide.to = overlay.width
        slide.start()
    }

    // ── Hover to pause auto-hide ──
    HoverHandler {
        id: hover
        onActiveChanged: {
            if (active) overlay.pauseAutoHide()
            else overlay.resumeAutoHide()
        }
    }
}
