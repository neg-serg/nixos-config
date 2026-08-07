pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Services.Notifications
import "../Helpers/Color.js" as Color

// NotificationCard — panel-dark card, even paddings, accent-tinted frame.

Rectangle {
    id: root
    required property Notification notif;
    required property var backer;

    // ── Metrics (even: content inset = frame + pad on every side) ──
    readonly property int _frameW: 1
    readonly property int _radius: 4
    readonly property int _pad: 12      // horizontal inset
    readonly property int _vpad: 10     // vertical inset
    readonly property int _iconSize: 48
    readonly property int _minW: 340
    readonly property int _maxW: 600
    readonly property color _fg: "#BFCAD0"
    readonly property color _accent: "#006FCC"

    // Panel-dark: ~0.9 alpha like the bar backdrop (0.88)
    width: Math.min(root._maxW, Math.max(root._minW, content.implicitWidth + 2 * (root._frameW + root._pad)))
    color: Qt.rgba(0, 0, 0, 0.95)
    radius: root._radius
    border.width: root._frameW
    border.color: Color.withAlpha(root._accent, 0.35)

    // ── Content: single column (main row + actions) ────────────────
    ColumnLayout {
        id: content
        x: root._frameW + root._pad
        y: root._frameW + root._vpad
        width: root.width - 2 * (root._frameW + root._pad)
        spacing: 8

        // ── Main row: icon + text column ───────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

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
                Layout.alignment: Qt.AlignVCenter

                readonly property string iconSource: {
                    if (root.notif.appIcon) return Quickshell.iconPath(root.notif.appIcon);
                    if (root.notif.image) return root.notif.image;
                    return "";
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3

                // Summary row: label + close (right-aligned)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Label {
                        id: summaryLabel
                        visible: root.notif.summary !== ""
                        text: root.notif.summary
                        font.family: "Iosevka"
                        font.weight: Font.Medium
                        font.pointSize: 13
                        color: root._fg
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Item {
                        Layout.preferredWidth: 24
                        Layout.preferredHeight: 24
                        Layout.alignment: Qt.AlignVCenter

                        Label {
                            anchors.centerIn: parent
                            text: "\u00D7"
                            font.family: "Iosevka"
                            font.pointSize: 15
                            color: root._fg
                            opacity: closeMa.containsMouse ? 1.0 : 0.6
                            Behavior on opacity { NumberAnimation { duration: 70 } }
                        }

                        MouseArea {
                            id: closeMa
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
                    font.pointSize: 12
                    color: root._fg
                    opacity: 0.85
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                }
            }
        }

        // ── Actions (counted in height — inside the column) ────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 0
            visible: root.notif.actions.length !== 0

            Repeater {
                model: root.notif.actions
                Item {
                    required property NotificationAction modelData;
                    required property int index;
                    Layout.fillWidth: true
                    implicitHeight: 34

                    Rectangle {
                        anchors {
                            top: parent.top; bottom: parent.bottom
                            left: parent.left; leftMargin: -0.5
                        }
                        visible: index !== 0
                        width: 1
                        color: Color.withAlpha(root._accent, 0.4)
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: { modelData.invoke(); root.backer.discard(); }

                        Label {
                            anchors.centerIn: parent
                            text: modelData.text
                            font.family: "Iosevka"
                            font.pointSize: 12
                            color: root._fg
                        }
                    }
                }
            }
        }
    }
}
