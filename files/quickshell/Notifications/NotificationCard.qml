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
    // Explicit height: without it the card renders at 0px and is invisible
    // (regression from "[gui/quickshell] Darken card bg and frame").
    height: Math.max(content.implicitHeight + 2 * (root._frameW + root._vpad), 64)
    color: Qt.rgba(0, 0, 0, 0.95)
    radius: root._radius
    border.width: root._frameW
    border.color: Color.withAlpha(root._accent, 0.12)

    // Pictogram for an action label — same style as ScreenshotToast's buttons.
    function actionPictogram(label: string): string {
        const l = label.toLowerCase();
        if (l.includes("open"))      return "\uD83D\uDCC2"; // 📂
        if (l.includes("reply"))     return "\uD83D\uDCAC"; // 💬
        if (l.includes("read"))      return "\u2713";       // ✓
        if (l.includes("dismiss") || l.includes("delete") || l.includes("clear") || l.includes("remove"))
                                     return "\uD83D\uDDD1"; // 🗑
        if (l.includes("accept") || l.includes("approve") || l === "yes")
                                     return "\u2705";       // ✅
        if (l.includes("decline") || l.includes("reject") || l === "no")
                                     return "\u274C";       // ❌
        if (l.includes("snooze"))    return "\u23F0";       // ⏰
        if (l.includes("mute"))      return "\uD83D\uDD15"; // 🔕
        if (l.includes("call"))      return "\uD83D\uDCDE"; // 📞
        if (l.includes("video"))     return "\uD83D\uDCF9"; // 📹
        if (l.includes("view"))      return "\uD83D\uDC41"; // 👁
        if (l.includes("download"))  return "\u2B07";       // ⬇
        if (l.includes("send"))      return "\uD83D\uDCE4"; // 📤
        if (l.includes("like"))      return "\uD83D\uDC4D"; // 👍
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
                    if (root.notif.appIcon) return Quickshell.iconPath(root.notif.appIcon);
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

        // ── Actions (toast-style buttons with pictograms, like ScreenshotToast) ──
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            visible: root.notif.actions.length !== 0

            Repeater {
                model: root.notif.actions
                Rectangle {
                    required property NotificationAction modelData;
                    Layout.preferredWidth: actText.implicitWidth + 20
                    Layout.preferredHeight: 30
                    radius: 6
                    color: actMa.containsMouse ? "#242A35" : "#181C24"
                    border.width: 1
                    border.color: "#3B4C5C"

                    Text {
                        id: actText
                        anchors.centerIn: parent
                        text: {
                            const pic = root.actionPictogram(modelData.text);
                            return pic !== "" ? pic + "  " + modelData.text : modelData.text;
                        }
                        font.family: "Iosevka"
                        font.weight: Font.Medium
                        font.pointSize: 10
                        color: root._fg
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

        Label {
            anchors.centerIn: parent
            text: "\u2715"
            font.family: "Iosevka"
            font.pointSize: 12
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
