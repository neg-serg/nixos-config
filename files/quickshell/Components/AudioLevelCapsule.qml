import QtQuick
import QtQuick.Layouts
import qs.Settings
import "." as LocalComponents
import "../Helpers/Utils.js" as Utils
import "../Helpers/WidgetBg.js" as WidgetBg

LocalComponents.WidgetCapsule {
    id: root

    property string settingsKey: ""
    property string iconOff: "volume_off"
    property string iconLow: "volume_down"
    property string iconHigh: "volume_up"
    property string labelSuffix: "%"
    property string labelText: ""
    property bool autoHideWhenMuted: false
    property bool panelHovering: false
    property bool wheelEnabled: true
    property string offReminderStateKey: ""
    readonly property int effectiveOffReminderCooldownMs: {
        const raw = Settings.settings ? Number(Settings.settings.audioOffReminderCooldownMs) : -1;
        if (isFinite(raw) && raw >= 0)
            return Math.round(raw);
        return Theme.panelVolumeOffReminderCooldownMs;
    }

    property int level: 0
    property bool muted: false
    property bool firstChange: true
    property string lastIconCategory: "up"
    property bool containsMouse: false

    // Track previous values so updateFrom() does not re-show the pill
    // when nothing actually changed (which prevents auto-hide from ever
    // completing).
    property int _prevClamped: -1
    property bool _prevMuted: false
    property string _prevCategory: ""

    readonly property alias pill: pillIndicator

    signal wheelStep(int direction)
    signal clicked

    backgroundKey: settingsKey
    centerContent: true
    forceHeightFromMetrics: true
    verticalPaddingScale: 0
    verticalPaddingMin: 0

    visible: false
    width: visible ? implicitWidth : 0
    height: visible ? implicitHeight : 0
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
            if (root.level === 100) {
                root.visible = false;
                pillIndicator.hide();
            }
        }
    }

    Timer {
        id: mutedHideTimer
        interval: Theme.panelVolumeMutedHideMs
        repeat: false
        onTriggered: {
            if (root.autoHideWhenMuted
                    && root.resolveIconCategory(root.level, root.muted) === "off"
                    && !root.panelHovering) {
                root.visible = false;
                pillIndicator.hide();
            }
        }
    }

    onPanelHoveringChanged: {
        if (!autoHideWhenMuted) return;
        if (resolveIconCategory(level, muted) !== "off") return;
        if (panelHovering) {
            if (!root.visible) {
                root.visible = true;
                pillIndicator.show();
            }
        } else {
            if (!mutedHideTimer.running) {
                root.visible = false;
                pillIndicator.hide();
            }
        }
    }

    function levelColorFor(value) {
        var t = Utils.clamp(value / 100.0, 0, 1);
        const lo = Theme.panelVolumeLowColor;
        const hi = Theme.panelVolumeHighColor;
        return Qt.rgba(lo.r + (hi.r - lo.r) * t, lo.g + (hi.g - lo.g) * t, lo.b + (hi.b - lo.b) * t, 1);
    }

    function resolveIconCategory(value, mutedValue) {
        if (mutedValue)
            return "off";
        if (value <= Theme.volumeIconOffThreshold)
            return "off";
        if (value < Theme.volumeIconDownThreshold)
            return "down";
        if (value >= Theme.volumeIconUpThreshold)
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

    function shouldShowOffReminder(category) {
        const enteringOff = category === "off" && _prevCategory !== "off";
        if (!enteringOff)
            return false;
        if (!offReminderStateKey.length || !StateCache.state)
            return true;

        const lastShownAt = Number(StateCache.state[offReminderStateKey] || 0);
        const now = Date.now();
        const expired = !isFinite(lastShownAt) || lastShownAt <= 0 || (now - lastShownAt) >= effectiveOffReminderCooldownMs;
        if (expired)
            StateCache.state[offReminderStateKey] = now;
        return expired;
    }

    function updateFrom(value, mutedValue) {
        const clamped = Utils.clamp(value, 0, 100);
        const category = resolveIconCategory(clamped, mutedValue);
        const showOffReminder = autoHideWhenMuted && shouldShowOffReminder(category);

        // Always update presentation (text, icon, colour)
        level = clamped;
        muted = mutedValue;
        pillIndicator.text = labelText.length ? labelText : clamped + labelSuffix;
        if (category !== "off")
            lastIconCategory = category;
        pillIndicator.icon = iconNameForCategory(category);
        const levelColor = levelColorFor(clamped);
        pillIndicator.iconCircleColor = levelColor;
        pillIndicator.collapsedIconColor = levelColor;

        if (autoHideWhenMuted && category === "off") {
            if (showOffReminder) {
                if (!root.visible)
                    root.visible = true;
                mutedHideTimer.restart();
                if (!firstChange)
                    pillIndicator.show();
            } else {
                if (mutedHideTimer.running)
                    mutedHideTimer.stop();
                root.visible = false;
                pillIndicator.hide();
            }
            firstChange = false;
            if (fullHideTimer.running)
                fullHideTimer.stop();
            _prevClamped = clamped;
            _prevMuted = mutedValue;
            _prevCategory = category;
            return;
        }

        if (mutedHideTimer.running)
            mutedHideTimer.stop();

        if (!root.visible && clamped !== 100)
            root.visible = true;

        // Only show the pill when the value *actually* changed, so the
        // auto-hide timer can complete instead of being restarted on
        // every idle sync.
        if (clamped !== _prevClamped || mutedValue !== _prevMuted)
            if (!firstChange || clamped !== 100)
                pillIndicator.show();
        _prevClamped = clamped;
        _prevMuted = mutedValue;
        _prevCategory = category;
        firstChange = false;

        if (clamped === 100) {
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
        pillColor: WidgetBg.color(Settings.settings, settingsKey, Theme.surface)
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
                if (!root.wheelEnabled || wheel.angleDelta.y === 0)
                    return;
                root.wheelStep(wheel.angleDelta.y > 0 ? 1 : -1);
            }
        }
    }

    default property alias extraContent: overlayLayer.data

    implicitWidth: horizontalPadding * 2 + Math.max(pillIndicator.width, capsuleMetrics.inner)
    implicitHeight: forceHeightFromMetrics ? Math.max(uniformCapsuleHeight, pillIndicator.height + verticalPadding * 2) : pillIndicator.height + verticalPadding * 2
}
