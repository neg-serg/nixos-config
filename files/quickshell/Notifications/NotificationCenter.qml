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

    // 580 = 560 (card max) + 2×10 (content margins) so cards aren't clipped
    readonly property int _panelW: 580
    implicitWidth: root._panelW
    readonly property color _fg: NotifColors.fg
    readonly property color _accent: NotifColors.accent

    visible: NotificationManager.showTrayNotifs

    // ── Backdrop ────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: NotifColors.panelBackground
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
        anchors.margins: 10
        spacing: 6


        // Scrollable list
        ListView {
            id: notifList
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 4
            clip: true
            // Active notifications first, dismissed ones below with an
            // "Earlier" header (Android-style history).
            model: {
                const out = NotificationManager.notifications.map(n => ({ item: n, isHeader: false }));
                if (NotificationManager.history.length > 0) {
                    out.push({ item: null, isHeader: true });
                    for (const n of NotificationManager.history) out.push({ item: n, isHeader: false });
                }
                return out;
            }

            delegate: Item {
                id: delegateRoot
                width: notifList.width
                required property var item;      // TrackedNotification | null (header)
                implicitHeight: delegateRoot.isHeader ? 28
                    : (cardLoader.item ? cardLoader.item.height : 0)

                // "Earlier" section header
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: delegateRoot.isHeader
                    text: "Earlier"
                    font.pointSize: 10
                    font.weight: Font.DemiBold
                    color: root._fg
                    opacity: 0.6
                }

                Loader {
                    id: cardLoader
                    anchors.fill: parent
                    active: !delegateRoot.isHeader
                    asynchronous: false
                    sourceComponent: NotificationCard {
                        notif: delegateRoot.item.notif
                        backer: delegateRoot.item
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (!delegateRoot.isHeader) delegateRoot.item.discard();
                    }
                }
            }
        }

        // Empty state
        Label {
            visible: NotificationManager.notifications.length === 0 && NotificationManager.history.length === 0
            text: "No notifications"
            color: root._fg
            opacity: 0.5
            font.pointSize: 15
            Layout.alignment: Qt.AlignCenter
            Layout.topMargin: 40
        }
    }

    onVisibleChanged: {
        if (root.visible) centerFocus.forceActiveFocus();
    }
}
