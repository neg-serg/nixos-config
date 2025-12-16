import QtQuick
import QtQuick.Layouts
import qs.Settings
import "." as LocalComponents
import "../Helpers/Utils.js" as Utils
import "../Helpers/WidgetBg.js" as WidgetBg

LocalComponents.WidgetCapsule {
    id: root

    property string settingsKey: ""
    property color pillBackground: WidgetBg.color(Settings.settings, settingsKey)
    property color gradientLow: Theme.panelVolumeLowColor
    property color gradientHigh: Theme.panelVolumeHighColor
    property string iconOff: "volume_off"
    property string iconLow: "volume_down"
    property string iconHigh: "volume_up"
    property int iconOffThreshold: Theme.volumeIconOffThreshold
    property int iconLowThreshold: Theme.volumeIconDownThreshold
    property int iconHighThreshold: Theme.volumeIconUpThreshold
    property string labelSuffix: "%"
    property bool autoHideAtFull: true
    property int fullHideValue: 100
    property bool collapseWhenHidden: true

    property int level: 0
    property bool muted: false
    property bool firstChange: true
    property string lastIconCategory: "up"
    property bool containsMouse: false

    readonly property alias pill: pillIndicator

    signal wheelStep(int direction)
    signal clicked

    backgroundKey: settingsKey
    centerContent: true
    forceHeightFromMetrics: false
    verticalPaddingScale: 0
    verticalPaddingMin: 0

    visible: false
    width: collapseWhenHidden ? (visible ? implicitWidth : 0) : implicitWidth
    height: collapseWhenHidden ? (visible ? implicitHeight : 0) : implicitHeight
    Layout.preferredWidth: width
    Layout.preferredHeight: height
    Layout.minimumWidth: width
    Layout.minimumHeight: height
    Layout.maximumWidth: width

    Timer {
        id: fullHideTimer
        interval: Theme.panelVolumeFullHideMs
        repeat: false
        onTriggered: {
            if (root.autoHideAtFull && root.level === root.fullHideValue) {
                root.visible = false;
                pillIndicator.hide();
            }
        }
    }

    function levelColorFor(value) {
        var t = Utils.clamp(value / 100.0, 0, 1);
        return Qt.rgba(gradientLow.r + (gradientHigh.r - gradientLow.r) * t, gradientLow.g + (gradientHigh.g - gradientLow.g) * t, gradientLow.b + (gradientHigh.b - gradientLow.b) * t, 1);
    }

    function resolveIconCategory(value, mutedValue) {
        if (mutedValue)
            return "off";
        if (value <= iconOffThreshold)
            return "off";
        if (value < iconLowThreshold)
            return "down";
        if (value >= iconHighThreshold)
            return "up";
        return lastIconCategory === "down" ? "down" : "up";
    }

    function iconNameForCategory(category) {
        switch (category) {
        case "off":
            return iconOff;
        case "down":
            return iconLow;
        case "up":
        default:
            return iconHigh;
        }
    }

    function updateFrom(value, mutedValue) {
        const clamped = Utils.clamp(value, 0, 100);
        level = clamped;
        muted = mutedValue;

        pillIndicator.text = clamped + labelSuffix;
        const category = resolveIconCategory(clamped, mutedValue);
        if (category !== "off")
            lastIconCategory = category;
        pillIndicator.icon = iconNameForCategory(category);

        const levelColor = levelColorFor(clamped);
        pillIndicator.iconCircleColor = levelColor;
        pillIndicator.collapsedIconColor = levelColor;

        if (!root.visible && (!autoHideAtFull || clamped !== fullHideValue)) {
            root.visible = true;
        }

        if (!firstChange || (!autoHideAtFull || clamped !== fullHideValue)) {
            pillIndicator.show();
        }
        firstChange = false;

        if (autoHideAtFull && clamped === fullHideValue) {
            fullHideTimer.restart();
        } else if (fullHideTimer.running) {
            fullHideTimer.stop();
        }
    }

    LocalComponents.PillIndicator {
        id: pillIndicator
        anchors.centerIn: parent
        icon: iconHigh
        text: "0" + labelSuffix
        pillColor: pillBackground
        iconCircleColor: levelColorFor(level)
        iconTextColor: Theme.background
        textColor: Theme.textPrimary
        collapsedIconColor: levelColorFor(level)
        autoHide: true
        autoHidePauseMs: Theme.volumePillAutoHidePauseMs
        showDelayMs: Theme.volumePillShowDelayMs
    }

    Item {
        id: overlayLayer
        parent: root
        anchors.fill: parent
        z: 10

        MouseArea {
            id: hoverArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.AllButtons
            onClicked: {
                if (mouse.button === Qt.LeftButton) {
                    root.clicked();
                }
            }
            onEntered: {
                root.containsMouse = true;
                pillIndicator.autoHide = false;
                pillIndicator.showDelayed();
            }
            onExited: {
                root.containsMouse = false;
                pillIndicator.autoHide = true;
                pillIndicator.hide();
            }
            onWheel: wheel => {
                if (wheel.angleDelta.y === 0)
                    return;
                root.wheelStep(wheel.angleDelta.y > 0 ? 1 : -1);
            }
        }
    }

    default property alias extraContent: overlayLayer.data

    implicitWidth: horizontalPadding * 2 + Math.max(pillIndicator.width, capsuleMetrics.inner)
    implicitHeight: forceHeightFromMetrics ? Math.max(capsuleMetrics.height, pillIndicator.height + verticalPadding * 2) : pillIndicator.height + verticalPadding * 2
}
