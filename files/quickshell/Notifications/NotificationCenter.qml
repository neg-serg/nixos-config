pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// NotificationCenter — notification history sidebar.
// Full-height panel on the right edge, displaces other surfaces.
// Toggled by NotificationManager.showTrayNotifs (via M4+n binding).

PanelWindow {
    id: root
    WlrLayershell.namespace: "shell:notification-center"
    exclusionMode: ExclusionMode.Normal
    color: "transparent"

    anchors {
        right: true
        top: true
        bottom: true
    }

    // 516 = 500 (card max) + 2×8 (content margins) so cards aren't clipped
    readonly property int _panelW: 516
    implicitWidth: root._panelW
    readonly property color _fg: "#BFCAD0"
    readonly property color _accent: "#6C7E96"

    visible: NotificationManager.showTrayNotifs

    // ── Backdrop ────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.85)
    }

    // ── Escape + focus ──────────────────────────────────────────────
    FocusScope {
        id: centerFocus
        anchors.fill: parent
        focus: root.visible
        Keys.onEscapePressed: NotificationManager.closeHistory()
    }

    // ── Content ─────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 6

        // Header bar
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 32

            Label {
                text: "Notifications"
                color: root._fg
                font.bold: true
                font.pointSize: 12
            }

            Item { Layout.fillWidth: true }

            // Clear all
            Rectangle {
                Layout.preferredWidth: clearLabel.implicitWidth + 16
                Layout.preferredHeight: 28
                radius: 4
                color: clearMa.containsMouse ? "#20ffffff" : "transparent"

                Label {
                    id: clearLabel
                    anchors.centerIn: parent
                    text: "Clear all"
                    color: root._fg
                    font.pointSize: 9
                }

                MouseArea {
                    id: clearMa
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: NotificationManager.sendDiscardAll()
                }
            }

            // Close
            Rectangle {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                radius: 4
                color: closeMa2.containsMouse ? "#20ffffff" : "transparent"

                Label {
                    anchors.centerIn: parent
                    text: "\u00D7"
                    color: root._fg
                    font.pointSize: 16
                }

                MouseArea {
                    id: closeMa2
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: NotificationManager.closeHistory()
                }
            }
        }

        // Divider
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: root._fg
            opacity: 0.15
        }

        // Scrollable list
        ListView {
            id: notifList
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 4
            clip: true
            model: NotificationManager.notifications

            delegate: Item {
                id: delegateRoot
                width: notifList.width
                implicitHeight: cardLoader.item ? cardLoader.item.implicitHeight : 0
                required property TrackedNotification modelData;

                Loader {
                    id: cardLoader
                    anchors.fill: parent
                    asynchronous: false
                    sourceComponent: NotificationCard {
                        notif: delegateRoot.modelData.notif
                        backer: delegateRoot.modelData
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: delegateRoot.modelData.discard()
                }
            }
        }

        // Empty state
        Label {
            visible: NotificationManager.notifications.length === 0
            text: "No notifications"
            color: root._fg
            opacity: 0.5
            font.pointSize: 12
            Layout.alignment: Qt.AlignCenter
            Layout.topMargin: 40
        }
    }

    onVisibleChanged: {
        if (root.visible) centerFocus.forceActiveFocus();
    }
}
