pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Services.Notifications
import qs.Components
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
    // Colors derived from the theme via formulas (see Helpers/Color.js):
    // text = lighten(theme text primary), accent = darken(theme accent primary).
    readonly property color _fg: Color.towardsWhite(Theme.textPrimary, 0.4)
    readonly property color _accent: Color.towardsBlack(Theme.accentPrimary, 0.3)

    // Panel-dark: ~0.9 alpha like the bar backdrop (0.88)
    width: Math.min(root._maxW, Math.max(root._minW, content.implicitWidth + 2 * (root._frameW + root._pad)))
    // Explicit height: without it the card renders at 0px and is invisible
    // (regression from "[gui/quickshell] Darken card bg and frame").
    height: Math.max(content.implicitHeight + 2 * (root._frameW + root._vpad), 64)
    color: Color.withAlpha(Theme.background, 0.95)
    radius: root._radius
    border.width: root._frameW
    border.color: Color.withAlpha(root._accent, 0.12)

    // Material icon name for an action label — same glyph set as the bar
    // and ScreenshotToast ("Material Symbols Outlined").
    function actionIcon(label: string): string {
        const l = label.toLowerCase();
        if (l.includes("open"))        return "folder_open";
        if (l.includes("reply"))       return "reply";
        if (l.includes("read"))        return "done";
        if (l.includes("dismiss") || l.includes("delete") || l.includes("clear") || l.includes("remove"))
                                       return "delete";
        if (l.includes("accept") || l.includes("approve") || l === "yes")
                                       return "check_circle";
        if (l.includes("decline") || l.includes("reject") || l === "no")
                                       return "cancel";
        if (l.includes("snooze"))      return "snooze";
        if (l.includes("mute"))        return "notifications_off";
        if (l.includes("call"))        return "call";
        if (l.includes("video"))       return "videocam";
        if (l.includes("view"))        return "visibility";
        if (l.includes("download"))    return "download";
        if (l.includes("send"))        return "send";
        if (l.includes("like"))        return "thumb_up";
        return "";
    }

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
                    const a = root.notif.appIcon;
                    if (a) {
                        // Some apps (e.g. Vivaldi) send a file:// URL or an absolute
                        // path as app icon instead of a theme icon name. The "icon"
                        // provider (QIcon::fromTheme) cannot resolve those, so load
                        // them directly as file URLs.
                        if (a.startsWith("file://")) return a;
                        if (a.startsWith("/")) return "file://" + a;
                        return Quickshell.iconPath(a);
                    }
                    if (root.notif.image) return root.notif.image;
                    return "";
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3

                // Summary: label only — close button is corner-anchored (top-right).
                Label {
                    id: summaryLabel
                    visible: root.notif.summary !== ""
                    text: root.notif.summary
                    font.family: "Iosevka"
                    font.weight: Font.DemiBold
                    font.pointSize: 11
                    color: root._fg
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                    Layout.rightMargin: 24 // keep clear of the corner close button
                }

                // Body
                Label {
                    id: bodyLabel
                    Layout.fillWidth: true
                    visible: root.notif.body !== ""
                    text: root.notif.body
                    font.weight: Font.Medium
                    font.pointSize: 10
                    color: root._fg
                    opacity: 0.85
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                }
            }
        }

        // ── Actions (toast-style buttons with Material icons, like ScreenshotToast) ──
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            visible: root.notif.actions.length !== 0

            Repeater {
                model: root.notif.actions
                Rectangle {
                    required property NotificationAction modelData;
                    Layout.preferredWidth: actRow.implicitWidth + 20
                    Layout.preferredHeight: 30
                    radius: 6
                    color: actMa.containsMouse ? Color.towardsBlack(Theme.outline, 0.42) : Color.towardsBlack(Theme.outline, 0.55)
                    border.width: 1
                    border.color: Theme.outline

                    RowLayout {
                        id: actRow
                        anchors.centerIn: parent
                        spacing: 5

                        MaterialIcon {
                            icon: root.actionIcon(modelData.text)
                            size: 13
                            color: root._fg
                            visible: root.actionIcon(modelData.text) !== ""
                        }

                        Text {
                            text: modelData.text
                            font.family: "Iosevka"
                            font.weight: Font.Medium
                            font.pointSize: 10
                            color: root._fg
                        }
                    }

                    MouseArea {
                        id: actMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: { modelData.invoke(); root.backer.discard(); }
                    }
                }
            }
        }
    }

    // ── Close button: anchored to the card's top-right corner ──
    Item {
        id: closeButton
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: root._frameW + 6
        anchors.rightMargin: root._frameW + 10
        width: 20
        height: 20
        z: 2

        MaterialIcon {
            anchors.centerIn: parent
            icon: "close"
            size: 12
            color: root._fg
            opacity: closeMa.containsMouse ? 1.0 : 0.6
            Behavior on opacity { NumberAnimation { duration: 70 } }
        }

        MouseArea {
            id: closeMa
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.backer.discard()
        }
    }
}
