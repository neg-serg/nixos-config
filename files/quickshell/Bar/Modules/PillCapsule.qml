import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Settings
import qs.Services as Services
import "../../Helpers/PillHistory.js" as PillHistory

OverlayToggleCapsule {
    id: root

    readonly property real capsuleScale: capsule.capsuleScale
    readonly property int iconBox: capsule.capsuleInner
    readonly property int fontPxMedium: Math.round(Theme.fontSizeMedium * capsuleScale)

    capsule.backgroundKey: "pills"
    capsule.centerContent: true
    capsule.cursorShape: Qt.PointingHandCursor
    capsule.implicitWidth: capsule.horizontalPadding * 2 + pillIcon.width
    capsuleVisible: !Services.PillTracker.taken
    autoToggleOnTap: false
    overlayNamespace: "pill-tracker"

    // Calendar navigation state
    property int calYear: new Date().getFullYear()
    property int calMonth: new Date().getMonth()

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
            PropertyAnimation { to: 0.3; duration: 800; easing.type: Easing.InOutSine }
            PropertyAnimation { to: 1.0; duration: 800; easing.type: Easing.InOutSine }
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

    // Right-click: open/close history overlay
    TapHandler {
        target: capsule
        acceptedButtons: Qt.RightButton
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: root.toggle()
    }

    overlayChildren: [
        PanelOverlaySurface {
            id: popup
            screen: root.screen
            scaleHint: capsuleScale

            Column {
                id: popupContent
                padding: Math.round(12 * capsuleScale)
                spacing: Math.round(8 * capsuleScale)

                // Streak header
                Row {
                    spacing: Math.round(6 * capsuleScale)
                    anchors.horizontalCenter: parent.horizontalCenter

                    MaterialIcon {
                        icon: "local_fire_department"
                        size: root.fontPxMedium
                        color: Services.PillTracker.streak > 0 ? "#FF6D00" : Theme.textSecondary
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: Services.PillTracker.streak + (Services.PillTracker.streak === 1 ? " day" : " days")
                        font.family: Theme.fontFamily
                        font.pixelSize: root.fontPxMedium
                        font.bold: true
                        color: Theme.textPrimary
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                // Month navigation
                Row {
                    spacing: Math.round(4 * capsuleScale)
                    anchors.horizontalCenter: parent.horizontalCenter

                    MaterialIcon {
                        icon: "chevron_left"
                        size: root.fontPxMedium
                        color: Theme.textSecondary
                        anchors.verticalCenter: parent.verticalCenter
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.calMonth === 0) {
                                    root.calMonth = 11;
                                    root.calYear--;
                                } else {
                                    root.calMonth--;
                                }
                            }
                        }
                    }
                    Text {
                        text: {
                            var names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                                         "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
                            return names[root.calMonth] + " " + root.calYear;
                        }
                        font.family: Theme.fontFamily
                        font.pixelSize: Math.round(Theme.fontSizeSmall * capsuleScale)
                        color: Theme.textPrimary
                        horizontalAlignment: Text.AlignHCenter
                        width: Math.round(80 * capsuleScale)
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    MaterialIcon {
                        icon: "chevron_right"
                        size: root.fontPxMedium
                        color: Theme.textSecondary
                        anchors.verticalCenter: parent.verticalCenter
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.calMonth === 11) {
                                    root.calMonth = 0;
                                    root.calYear++;
                                } else {
                                    root.calMonth++;
                                }
                            }
                        }
                    }
                }

                // Day-of-week headers
                Grid {
                    id: dayHeaders
                    columns: 7
                    columnSpacing: Math.round(2 * capsuleScale)
                    anchors.horizontalCenter: parent.horizontalCenter

                    Repeater {
                        model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
                        Text {
                            required property string modelData
                            text: modelData
                            font.family: Theme.fontFamily
                            font.pixelSize: Math.round((Theme.fontSizeSmall - 1) * capsuleScale)
                            color: Theme.textSecondary
                            horizontalAlignment: Text.AlignHCenter
                            width: Math.round(24 * capsuleScale)
                        }
                    }
                }

                // Calendar grid
                Grid {
                    id: calendarGrid
                    columns: 7
                    columnSpacing: Math.round(2 * capsuleScale)
                    rowSpacing: Math.round(2 * capsuleScale)
                    anchors.horizontalCenter: parent.horizontalCenter

                    readonly property var cells: PillHistory.calendarData(
                        root.calYear, root.calMonth,
                        { date: Services.PillTracker.todayDate,
                          taken: Services.PillTracker.taken,
                          takenAt: Services.PillTracker.takenAt },
                        Services.PillTracker.history
                    )

                    Repeater {
                        model: calendarGrid.cells

                        Rectangle {
                            required property var modelData
                            required property int index

                            width: Math.round(24 * capsuleScale)
                            height: width
                            radius: width / 2
                            color: {
                                if (!modelData.inMonth) return "transparent";
                                if (modelData.status === "taken") return Qt.rgba(Theme.accentPrimary.r, Theme.accentPrimary.g, Theme.accentPrimary.b, 0.3);
                                if (modelData.status === "missed") return Qt.rgba(1, 0.3, 0.3, 0.25);
                                return "transparent";
                            }
                            border.width: {
                                if (!modelData.inMonth) return 0;
                                var todayStr = PillHistory.currentDateStr();
                                var m = String(root.calMonth + 1).padStart(2, "0");
                                var d = String(modelData.day).padStart(2, "0");
                                var cellDate = root.calYear + "-" + m + "-" + d;
                                return cellDate === todayStr ? 1 : 0;
                            }
                            border.color: Theme.accentPrimary

                            Text {
                                anchors.centerIn: parent
                                text: modelData.inMonth ? modelData.day : ""
                                font.family: Theme.fontFamily
                                font.pixelSize: Math.round((Theme.fontSizeSmall - 1) * capsuleScale)
                                color: modelData.status === "taken" ? Theme.accentPrimary
                                     : modelData.status === "missed" ? Theme.textSecondary
                                     : Theme.textDisabled
                                font.bold: modelData.status === "taken"
                            }
                        }
                    }
                }
            }
        }
    ]

    onOpened: {
        var now = new Date();
        root.calYear = now.getFullYear();
        root.calMonth = now.getMonth();
    }
}
