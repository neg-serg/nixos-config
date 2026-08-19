pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Services

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

    visible: NotificationManager.showTrayNotifs && !HyprlandWatcher.hideUi

    // ── Backdrop ────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: NotifColors.panelBackground
    }

    // ── Escape + focus ──────────────────────────────────────────────
    // Emacs-style list navigation (additive; mouse still works):
    //   C-n/C-p move down/up, C-f/C-b page down/up, C-a/C-e first/last,
    //   C-k or Enter discard the notification under the cursor.
    FocusScope {
        id: centerFocus
        anchors.fill: parent
        focus: root.visible
        Keys.onEscapePressed: NotificationManager.closeHistory()
        Keys.onPressed: function(event) {
            if (notifList.count === 0) return;

            const ctrl = (event.modifiers & Qt.ControlModifier)
                && !(event.modifiers & (Qt.ShiftModifier | Qt.AltModifier | Qt.MetaModifier));
            let idx = notifList.currentIndex;
            let target = -1;

            if (ctrl) {
                switch (event.key) {
                case Qt.Key_N: target = idx < 0 ? 0 : Math.min(idx + 1, notifList.count - 1); break;
                case Qt.Key_P: target = idx < 0 ? 0 : Math.max(idx - 1, 0); break;
                case Qt.Key_F: target = idx < 0 ? 0 : Math.min(idx + 5, notifList.count - 1); break;
                case Qt.Key_B: target = idx < 0 ? 0 : Math.max(idx - 5, 0); break;
                case Qt.Key_A: target = 0; break;
                case Qt.Key_E: target = notifList.count - 1; break;
                case Qt.Key_K: {
                    idx = idx < 0 ? 0 : idx;
                    notifList.currentIndex = idx;
                    notifList.positionViewAtIndex(idx, ListView.Center);
                    const dismissed = notifList.model[idx];
                    if (dismissed && dismissed.item && !dismissed.isHeader) dismissed.item.discard();
                    event.accepted = true;
                    return;
                }
                default: return;
                }
                if (target >= 0) {
                    notifList.currentIndex = target;
                    notifList.positionViewAtIndex(target, ListView.Center);
                    event.accepted = true;
                }
                return;
            }

            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                const i = idx < 0 ? 0 : idx;
                notifList.currentIndex = i;
                notifList.positionViewAtIndex(i, ListView.Center);
                const entry = notifList.model[i];
                if (entry && entry.item && !entry.isHeader) entry.item.discard();
                event.accepted = true;
            }
        }
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
                required property bool isHeader;  // model provides {item, isHeader}
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
                        notif: delegateRoot.item
                        backer: delegateRoot.item
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (!delegateRoot.isHeader) delegateRoot.item.discard();
                    }
                }

                // Keyboard-navigation highlight (emacs C-n/C-p …)
                Rectangle {
                    visible: delegateRoot.ListView.isCurrentItem
                    anchors.fill: parent
                    radius: 4
                    color: root._accent
                    opacity: 0.15
                    z: 2
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
