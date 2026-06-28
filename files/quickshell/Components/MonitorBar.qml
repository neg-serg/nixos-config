import QtQuick
import qs.Settings
import "../Helpers/SystemMonitorUi.js" as SysUi

/*!
 * MonitorBar — compact vertical bar for displaying a 0–1 metric value.
 * Height fills proportionally; color shifts at configurable thresholds.
 */
Rectangle {
    id: root

    property real value: 0.0
    property int barWidth: {
        var v = Settings.settings.systemMonitorBarWidth;
        var base = (typeof v === "number" && v > 0) ? v : 3;
        return Math.max(2, Math.round(base * Theme.scale(screen)));
    }
    property int barHeight: Math.round(Theme.panelHeight * 0.6 * Theme.scale(screen))
    property var screen: null

    property color neutralColor: Theme.textSecondary
    property color warnColor: Theme.warning
    property color critColor: Theme.error
    property real warnThreshold: 0.5
    property real critThreshold: 0.8

    width: barWidth
    height: barHeight
    color: "transparent"
    clip: true

    readonly property real _clampedValue: Math.max(0, Math.min(1, value))
    readonly property color _barColor: SysUi.thresholdColor(
        _clampedValue, neutralColor, warnColor, critColor, warnThreshold, critThreshold)

    Rectangle {
        id: fill
        anchors.bottom: parent.bottom
        width: parent.width
        height: Math.round(root._clampedValue * root.barHeight)
        radius: Math.round(root.barWidth / 2)
        color: root._barColor

        Behavior on height {
            enabled: Theme._themeLoaded && Theme.animationsEnabled
            NumberStdOutBehavior {}
        }
        Behavior on color {
            enabled: Theme._themeLoaded && Theme.animationsEnabled
            ColorFastInOutBehavior {}
        }
    }
}
