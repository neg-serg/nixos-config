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
    // Optional custom SVG icon (e.g. Genelec "The Ones") replacing the glyph.
    property string iconSource: ""
    property string labelSuffix: "%"
    property string labelText: ""
    property bool autoHideWhenMuted: false
    property bool panelHovering: false
    property bool wheelEnabled: true
    // Keep the pill (icon + text) permanently visible instead of auto-hiding.
    // Used by the Genelec widget during debugging; default preserves the
    // standard hover/show behavior for all other volume widgets.
    property bool alwaysShow: false
    // Reveal the level pill when the cursor hovers the capsule. Uses the same
    // delayed-reveal timer as the tooltip (volumePillShowDelayMs waits, then
    // shows). Toggle: Settings.json "showVolumeOnHover" (default true, applies
    // to all audio-level capsules: volume, microphone, Genelec).
    property bool showOnHover: Settings.settings ? Settings.settings.showVolumeOnHover !== false : true
    // Hide the idle (collapsed) icon until the capsule is hovered. Used for the
    // Genelec monitor icon so the bar stays clean while idle.
    property bool hideIconWhenIdle: false
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

    // When the monitor icon is hidden while idle (Genelec), also collapse the
    // whole capsule so nothing black sticks out at the bar edge. The capsule
    // keeps its hover geometry (opacity does not disable input) so hovering the
    // area still reveals the icon+pill; panelHovering keeps it visible too.
    // The pill (e.g. a volume change from the keyboard) must also keep the
    // capsule visible until it auto-hides, otherwise the OSD cannot pop up
    // while the cursor is away from the panel.
    readonly property real _idleOpacity: (root.hideIconWhenIdle && !root.containsMouse && !root.panelHovering && !root.pill.showPill) ? 0 : 1

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
    // Idle-hidden monitor capsules (Genelec) must also collapse their width,
    // otherwise the bar keeps an empty slot where the invisible capsule sits.
    width: (visible && root._idleOpacity > 0) ? implicitWidth : 0
    height: visible ? implicitHeight : 0
    Layout.preferredWidth: width
    Layout.preferredHeight: height
    Layout.minimumWidth: width
    Layout.minimumHeight: height
    Layout.maximumWidth: width
    // Ease the idle collapse so the capsule never vanishes/snaps abruptly.
    opacity: root._idleOpacity
    Behavior on opacity { NumberAnimation { duration: 260 } }
    // Hover-out grace: delay collapsing the pill after the cursor leaves.
    Timer {
        id: hoverOutTimer
        interval: Theme.volumePillAutoHidePauseMs
        repeat: false
        onTriggered: {
            if (!root.containsMouse && !root.alwaysShow) pillIndicator.hide();
        }
    }

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

        // A keyboard volume/mute event must bring the indicator up even when
        // the value is already capped (0% or 100%) and therefore "unchanged".
        const wasHidden = !root.visible;
        root.visible = true;
        const changed = (clamped !== _prevClamped || mutedValue !== _prevMuted);

        // Only show the pill when the value actually changed, or when the
        // capsule was hidden and the user pressed volume at a cap — so the
        // auto-hide timer can complete instead of being restarted by idle syncs.
        if (changed || (wasHidden && (clamped <= 0 || clamped >= 100)))
            if (!firstChange || clamped !== 100)
                pillIndicator.show();
        if (Settings.settings && Settings.settings.debugLogs)
            console.debug("[vol] updateFrom clamped=" + clamped + " visible=" + root.visible
                + " showPill=" + pillIndicator.showPill + " changed=" + changed);
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
        iconSource: root.iconSource
        text: "0" + labelSuffix
        pillColor: WidgetBg.color(Settings.settings, settingsKey, Theme.surface)
        iconCircleColor: levelColorFor(level)
        iconTextColor: Theme.background
        // Digits in the pill keep the ordinary text colour (no level tint).
        textColor: Theme.textPrimary
        collapsedIconColor: levelColorFor(level)
        // No circle behind the audio icon; icon colour follows the level.
        showDisc: false
        // Hide the idle icon until the capsule is hovered (Genelec monitor).
        hideIconWhenIdle: root.hideIconWhenIdle
        hovered: root.containsMouse || root.panelHovering
        // Digits stay in the ordinary text colour; the unit sign ("dB" / "%")
        // and a leading minus are painted with the wallpaper accent.
        colorizeUnit: true
        accentUnitColor: Theme.accentPrimary
        autoHide: !root.alwaysShow
        autoHidePauseMs: Theme.volumePillAutoHidePauseMs
        showDelayMs: Theme.volumePillShowDelayMs
        Component.onCompleted: {
            if (root.alwaysShow) {
                root.pill.autoHide = false;
                root.pill.show();
            }
        }
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
                hoverOutTimer.stop();
                if (!root.showOnHover) return;
                pillIndicator.autoHide = false;
                pillIndicator.showDelayed();
            }
            onExited: {
                root.containsMouse = false;
                // Keep the pill for a short grace period after the cursor leaves
                // (hover-out delay) instead of collapsing it instantly.
                if (!root.alwaysShow) {
                    pillIndicator.autoHide = true;
                    hoverOutTimer.restart();
                }
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
