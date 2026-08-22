import QtQuick
import qs.Components
import qs.Settings
import qs.Services as Services

OverlayToggleCapsule {
    id: root

    readonly property real capsuleScale: capsule.capsuleScale
    readonly property int iconBox: capsule.capsuleInner

    capsule.backgroundKey: "pills"
    capsule.centerContent: true
    capsule.cursorShape: Qt.PointingHandCursor
    capsule.implicitWidth: capsule.horizontalPadding * 2 + pillIcon.width
    capsuleVisible: !Services.PillTracker.taken
    autoToggleOnTap: false

    MaterialIcon {
        id: pillIcon
        icon: "pill"
        size: iconBox
        color: Services.PillTracker.taken ? Theme.accentPrimary : Theme.textSecondary
        anchors.centerIn: parent

        Behavior on color {
            enabled: Theme._themeLoaded && Theme.animationsEnabled
            ColorFastInOutBehavior {}
        }

        SequentialAnimation on opacity {
            id: pulseAnimation
            running: Services.PillTracker.reminderActive && !(Settings.settings.reducedMotion)
            loops: Animation.Infinite
            PropertyAnimation { to: 0.3; duration: 500; easing.type: Easing.InOutSine }
            PropertyAnimation { to: 1.0; duration: 500; easing.type: Easing.InOutSine }
            onRunningChanged: if (!running) pillIcon.opacity = 1.0
        }
    }

    PanelTooltip {
        targetItem: pillIcon
        text: Services.PillTracker.taken
            ? "Taken at " + Services.PillTracker.takenAt
            : Services.PillTracker.reminderActive
                ? "Not taken yet!"
                : "Not taken yet"
        visibleWhen: capsule.hovered && !root.expanded
    }

    // Left-click: toggle pill state
    TapHandler {
        target: capsule
        acceptedButtons: Qt.LeftButton
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: Services.PillTracker.toggle()
    }

    // Right-click: open the shared calendar (same overlay as the clock)
    TapHandler {
        target: capsule
        acceptedButtons: Qt.RightButton
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: pillCalendar.toggle()
    }

    // Reuse the clock's calendar overlay; enable the pill history markers.
    Calendar {
        id: pillCalendar
        screen: root.screen
        showPill: true
    }
}
