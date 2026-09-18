import QtQuick
import QtQuick.Window
import qs.Settings
import "../Helpers/ScreenUtil.js" as ScreenUtil
import qs.Components
import "../Helpers/Utils.js" as Utils

Window {
    id: tooltipWindow
    property string text: ""
    property bool tooltipVisible: false
    property Item targetItem: null
    property int delay: Theme.tooltipDelayMs
    property bool positionAbove: true

    flags: Qt.ToolTip | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
    color: "transparent"
    visible: false

    property Timer _timer: Timer {
        interval: tooltipWindow.delay
        onTriggered: tooltipWindow.showNow()
    }

    property real minSize: Theme.tooltipMinSize * scaleFactor
    property real scaleFactor: Theme.scale ? Theme.scale(screen) : 1
    property real margin: Theme.tooltipMargin * scaleFactor
    property real padding: Theme.tooltipPadding * scaleFactor

    onTooltipVisibleChanged: {
        if (tooltipVisible) {
            if (delay > 0) {
                _timer.restart();
            } else {
                showNow();
            }
        } else {
            hideNow();
        }
    }

    function updateSize() {
        if (!tooltipText) return;

        var contentWidth = tooltipText.implicitWidth + 2 * padding;
        var contentHeight = tooltipText.implicitHeight + 2 * padding;
        width = Utils.clamp(contentWidth, minSize, contentWidth);
        height = Utils.clamp(contentHeight, minSize, contentHeight);
    }

    function showNow() {
        if (!targetItem || !targetItem.visible) {
            hideNow();
            return;
        }

        updateSize();
        var screenGeometry = getScreenGeometry();
        if (!screenGeometry) screenGeometry = getFallbackGeometry();

        var globalPos = targetItem.mapToGlobal(0, 0);
        var targetHeight = targetItem.height;

        var proposedY = globalPos.y - height - margin;
        var finalPositionAbove = true;

        if (proposedY < screenGeometry.y) {
            proposedY = globalPos.y + targetHeight + margin;
            finalPositionAbove = false;
        }

        // Horizontal centering
        var proposedX = globalPos.x + (targetItem.width - width) / 2;

        if (proposedX < screenGeometry.x) {
            proposedX = screenGeometry.x;
        } else if (proposedX + width > screenGeometry.x + screenGeometry.width) {
            proposedX = screenGeometry.x + screenGeometry.width - width;
        }

        if (finalPositionAbove) {
            proposedY = Utils.clamp(proposedY, screenGeometry.y, proposedY);
        } else {
            if (proposedY + height > screenGeometry.y + screenGeometry.height) {
                proposedY = globalPos.y - height - margin;
                finalPositionAbove = true;
                proposedY = Utils.clamp(proposedY, screenGeometry.y, proposedY);
            }
        }

        x = proposedX;
        y = proposedY;
        positionAbove = finalPositionAbove;
        visible = true;
    }

    // The screen's rectangle, via ScreenUtil (which resolves the screen without
    // touching the Screen attached property — that one crashes when the window
    // has no screen yet). Before: every candidate was tested with
    // `screen.virtualGeometry`, a property no screen here has, so this always
    // returned null and the tooltip positioned itself in a fixed 1000x1000 box
    // around the target instead of inside the monitor.
    function getScreenGeometry() {
        return ScreenUtil.geometry(targetItem)
    }

    function getFallbackGeometry() {
        var globalPos = targetItem.mapToGlobal(0, 0);
        return Qt.rect(
            globalPos.x - 500,
            globalPos.y - 500,
            1000,  // width
            1000   // height
        );
    }

    function hideNow() {
        visible = false;
        _timer.stop();
    }

    Connections {
        target: tooltipWindow.targetItem
        ignoreUnknownSignals: true

        function onXChanged() { if (visible) showNow(); }
        function onYChanged() { if (visible) showNow(); }
        function onWidthChanged() { if (visible) showNow(); }
        function onHeightChanged() { if (visible) showNow(); }
        function onVisibleChanged() { if (!targetItem.visible) hideNow(); }
        function onDestroyed() {
            tooltipWindow.targetItem = null;
            tooltipWindow.tooltipVisible = false;
        }
    }

    Rectangle {
        id: tooltipBg
        anchors.fill: parent
        radius: Theme.panelMenuRadius * scaleFactor
        color: Theme.background
        border.color: Theme.borderSubtle
        border.width: Theme.uiBorderWidth * scaleFactor
        z: 1
    }

    ContrastGuard { id: ttContrast; bg: tooltipBg.color; label: 'Tooltip' }

    Text {
        id: tooltipText
        text: tooltipWindow.text
        color: ttContrast.fg
        font.family: Theme.fontFamily || "Arial"
        font.pixelSize: Theme.tooltipFontPx * scaleFactor
        anchors.centerIn: parent
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        wrapMode: Text.Wrap
        padding: padding
        z: 2
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onExited: tooltipWindow.tooltipVisible = false
        cursorShape: Qt.ArrowCursor
    }

    // Update when text changes
    onTextChanged: {
        updateSize();
        if (visible) showNow();
    }

    onScreenChanged: if (visible) Qt.callLater(showNow)
}
