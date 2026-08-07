pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Services.Notifications

// NotificationCard — compact panel-style card.
// Single-row header (icon 32px + summary), body below, thin frame.

Rectangle {
    id: root
    required property Notification notif;
    required property var backer;

    // ── Metrics ────────────────────────────────────────────────────
    readonly property int _frameW: 1
    readonly property int _radius: 4
    readonly property int _hpad: 8
    readonly property int _iconSize: 32
    readonly property int _minW: 260
    readonly property int _maxW: 480
    readonly property color _fg: "#BFCAD0"
    readonly property color _frame: "#3B4C5C"

    // Compact panel-like size: 16 = 2*(frame 1 + hpad 8)
    width: Math.min(root._maxW, Math.max(root._minW, mainLayout.implicitWidth + 16))
    height: Math.max(mainLayout.implicitHeight + root._frameW * 2, 44)
    color: Qt.rgba(0, 0, 0, 0.75)
    radius: root._radius
    border.width: root._frameW
    border.color: root._frame

    RowLayout {
        id: mainLayout
        x: root._frameW + root._hpad
        y: root._frameW
        width: root.width - root._frameW * 2 - root._hpad * 2
        spacing: 8

        // Icon — small, left
        Image {
            id: iconImage
            visible: iconSource !== ""
            source: iconSource
            fillMode: Image.PreserveAspectFit
            antialiasing: true
            sourceSize.width: root._iconSize
            sourceSize.height: root._iconSize
            Layout.preferredWidth: root._iconSize
            Layout.preferredHeight: root._iconSize

            readonly property string iconSource: {
                if (root.notif.appIcon) return Quickshell.iconPath(root.notif.appIcon);
                if (root.notif.image) return root.notif.image;
                return "";
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            // Summary row
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Label {
                    id: summaryLabel
                    visible: root.notif.summary !== ""
                    text: root.notif.summary
                    font.family: "Iosevka"
                    font.weight: Font.Medium
                    font.pointSize: 10
                    color: root._fg
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                // Close ×
                Item {
                    Layout.preferredWidth: 18
                    Layout.preferredHeight: 18

                    Label {
                        anchors.centerIn: parent
                        text: "\u00D7"
                        font.family: "Iosevka"
                        font.pointSize: 11
                        color: root._fg
                        opacity: closeMa.containsMouse ? 1.0 : 0.6
                        Behavior on opacity { NumberAnimation { duration: 120 } }
                    }

                    MouseArea {
                        id: closeMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.backer.discard()
                    }
                }
            }

            // Body
            Label {
                id: bodyLabel
                Layout.fillWidth: true
                visible: root.notif.body !== ""
                text: root.notif.body
                font.family: "Iosevka"
                font.pointSize: 9
                color: root._fg
                opacity: 0.85
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
            }
        }
    }

    // Actions strip (when present)
    RowLayout {
        id: actionsRow
        anchors.left: mainLayout.left
        anchors.right: mainLayout.right
        anchors.top: mainLayout.bottom
        spacing: 0
        visible: root.notif.actions.length !== 0

        Repeater {
            model: root.notif.actions
            Item {
                required property NotificationAction modelData;
                required property int index;
                Layout.fillWidth: true
                implicitHeight: 24

                Rectangle {
                    anchors {
                        top: parent.top; bottom: parent.bottom
                        left: parent.left; leftMargin: -0.5
                    }
                    visible: index !== 0
                    width: 1
                    color: root._frame
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: { modelData.invoke(); root.backer.discard(); }

                    Label {
                        anchors.centerIn: parent
                        text: modelData.text
                        font.family: "Iosevka"
                        font.pointSize: 9
                        color: root._fg
                    }
                }
            }
        }
    }
}
