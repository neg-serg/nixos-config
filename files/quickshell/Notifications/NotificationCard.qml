pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Services.Notifications

// NotificationCard — dunst replica.
// Font: Iosevka Medium 10pt, #000000 bg at 75% opacity,
// frame: 10px #000000, radius: 4, fg: #BFCAD0,
// hpadding: 6, vpadding: 0, icon ≤96px left of full content,
// width dynamic (300–500) like dunst.

Rectangle {
    id: root
    required property Notification notif;
    required property var backer;

    // ── Dunst metrics ──────────────────────────────────────────────
    readonly property int _frameW: 10
    readonly property int _radius: 4
    readonly property int _hpad: 6
    readonly property int _iconSize: 96
    readonly property int _minW: 300
    readonly property int _maxW: 500
    readonly property color _fg: "#BFCAD0"
    readonly property color _accent: "#3B4C5C"

    // Dynamic width like dunst's (300, 500): content-driven, clamped.
    // 32 = 2*(frame 10 + hpad 6)
    width: Math.min(root._maxW, Math.max(root._minW, mainLayout.implicitWidth + 32))
    // Minimum height guard: without it a stale build lost the height binding
    // and cards rendered at 0px (invisible). 40 = frame 20 + minimal content.
    height: Math.max(mainLayout.implicitHeight + root._frameW * 2, 40)
    color: Qt.rgba(0, 0, 0, 0.75)
    radius: root._radius
    border.width: root._frameW
    border.color: "#000000"

    // ── Main: icon left of full content column ─────────────────────
    RowLayout {
        id: mainLayout
        x: root._frameW + root._hpad
        y: root._frameW
        width: root.width - root._frameW * 2 - root._hpad * 2
        spacing: root._hpad

        // Icon — spans the full notification height, centered vertically
        Image {
            id: iconImage
            // Icon: appIcon (theme lookup) falls back to image-data hint
            visible: iconSource !== ""
            source: iconSource
            fillMode: Image.PreserveAspectFit
            antialiasing: true
            sourceSize.width: root._iconSize
            sourceSize.height: root._iconSize
            Layout.preferredWidth: root._iconSize
            Layout.preferredHeight: root._iconSize
            Layout.maximumWidth: root._iconSize
            Layout.maximumHeight: root._iconSize

            readonly property string iconSource: {
                if (root.notif.appIcon) return Quickshell.iconPath(root.notif.appIcon);
                if (root.notif.image) return root.notif.image;
                return "";
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            // ── Summary row + close ───────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: root._hpad

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

                // Close — 24×24 hit target, centered ×
                Item {
                    Layout.preferredWidth: 24
                    Layout.preferredHeight: 24
                    visible: root.notif.summary !== "" || root.notif.body !== ""

                    Label {
                        anchors.centerIn: parent
                        text: "\u00D7"
                        font.family: "Iosevka"
                        font.pointSize: 13
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

            // ── Body ─────────────────────────────────────────────
            Label {
                id: bodyLabel
                Layout.fillWidth: true
                visible: root.notif.body !== ""
                text: root.notif.body
                font.family: "Iosevka"
                font.weight: Font.Medium
                font.pointSize: 10
                color: root._fg
                wrapMode: Text.Wrap
            }

            // ── Actions ───────────────────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                visible: root.notif.actions.length !== 0

                Rectangle {
                    height: 1
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    Layout.bottomMargin: 2
                    color: root._accent
                }

                RowLayout {
                    spacing: 0
                    Repeater {
                        model: root.notif.actions
                        Item {
                            required property NotificationAction modelData;
                            required property int index;
                            Layout.fillWidth: true
                            implicitHeight: 28

                            Rectangle {
                                anchors {
                                    top: parent.top; bottom: parent.bottom
                                    left: parent.left; leftMargin: -0.5
                                }
                                visible: index !== 0
                                width: 1
                                color: root._accent
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: { modelData.invoke(); root.backer.discard(); }

                                Label {
                                    anchors.centerIn: parent
                                    text: modelData.text
                                    font.family: "Iosevka"
                                    font.pointSize: 10
                                    color: root._fg
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
