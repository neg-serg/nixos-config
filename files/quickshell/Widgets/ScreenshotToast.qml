import QtQuick 2.15
import QtQuick.Layouts 1.15
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

/*!
 * ScreenshotToast — macOS-style floating screenshot feedback card.
 * FileView watches the semaphore ~/.cache/quickshell/screenshot-event.
 * On trigger, reads JSON data via XMLHttpRequest (local file:// URL).
 * Auto-dismisses after 5s.
 */
Item {
    id: root
    visible: false

    readonly property string _home: {
        var h = Quickshell.env("HOME");
        return (h && h !== "") ? h : "/tmp";
    }
    readonly property string _triggerPath: root._home + "/.cache/quickshell/screenshot-event"
    readonly property string _dataUrl:    "file://" + root._home + "/.cache/quickshell/screenshot-event.json"

    FileView {
        id: triggerFile
        path: root._triggerPath
        watchChanges: true
        onFileChanged: {
            root.loadAndShow();
            reload();
        }
    }

    // ── Parsed metadata ──────────────────────────────────────────────────
    property string shotPath: ""
    property int shotW: 0
    property int shotH: 0
    property string shotSizeHr: ""
    property string shotDepth: ""
    property string shotTs: ""

    function loadAndShow() {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", root._dataUrl);
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200 || xhr.status === 0) {
                    try {
                        var data = JSON.parse(xhr.responseText);
                        root.shotPath   = data.path   || "";
                        root.shotW      = data.w      || 0;
                        root.shotH      = data.h      || 0;
                        root.shotSizeHr = data.sizeHr || "";
                        root.shotDepth  = data.depth  || "";
                        root.shotTs     = data.ts     || "";
                        toast.show();
                    } catch (e) {}
                }
            }
        };
        xhr.send();
    }

    // ── Toast window ─────────────────────────────────────────────────────
    PanelWindow {
        id: toast
        color: "transparent"
        visible: false

        WlrLayershell.namespace: "qs-screenshot"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusionMode: ExclusionMode.Ignore

        anchors.right: true
        anchors.bottom: true
        WlrLayershell.margins { right: 24; bottom: 24 }

        implicitWidth: 360
        implicitHeight: 160

        property int autoHideMs: 5000
        Timer {
            id: autoHide
            interval: toast.autoHideMs
            repeat: false
            onTriggered: toast.hide()
        }

        function show() {
            slide.stop(); _hiding = false; visible = true;
            slide.from = 40; slide.to = 0; slide.start();
            autoHide.restart();
        }
        function hide() {
            slide.stop(); _hiding = true;
            slide.from = slideY; slide.to = 40; slide.start();
        }

        property real slideY: 40
        property bool _hiding: false
        NumberAnimation {
            id: slide
            target: toast; property: "slideY"
            duration: 200; easing.type: Easing.OutCubic
            onStopped: { if (toast._hiding) { toast.visible = false; toast._hiding = false; } }
        }

        Rectangle {
            anchors.fill: parent
            radius: 12
            color: Qt.rgba(0.11, 0.11, 0.16, 0.92)
            border.width: 1
            border.color: Qt.rgba(0.30, 0.35, 0.45, 0.30)
            transform: Translate { y: toast.slideY }

            HoverHandler {
                onActiveChanged: { if (active) autoHide.stop(); else autoHide.restart(); }
            }
            TapHandler {
                onTapped: {
                    Quickshell.execDetached(["xdg-open", root.shotPath]);
                    toast.hide();
                }
            }

            ColumnLayout {
                anchors.fill: parent; anchors.margins: 16; spacing: 8

                RowLayout {
                    Layout.fillWidth: true; spacing: 10

                    Rectangle {
                        Layout.preferredWidth: 56; Layout.preferredHeight: 42
                        radius: 8
                        color: Qt.rgba(0.18, 0.18, 0.26, 0.60)
                        border.width: 1
                        border.color: Qt.rgba(0.35, 0.40, 0.50, 0.25)
                        Image {
                            anchors.fill: parent; anchors.margins: 2
                            source: root.shotPath ? "file://" + root.shotPath : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            visible: root.shotPath !== ""
                        }
                        Text {
                            anchors.centerIn: parent
                            text: "\uD83D\uDCF8"; font.pixelSize: 20
                            visible: root.shotPath === ""
                        }
                    }

                    ColumnLayout {
                        spacing: 2
                        Text { text: "Screenshot captured"; color: "#C8D6E5"; font.pixelSize: 13; font.weight: Font.DemiBold }
                        Text {
                            text: root.shotW + "\u202F\u00D7\u202F" + root.shotH
                                 + "  \u00B7  " + root.shotSizeHr
                                 + (root.shotDepth !== "" ? "  \u00B7  " + root.shotDepth : "")
                            color: "#8395A7"; font.pixelSize: 11
                        }
                    }

                    Item { Layout.fillWidth: true }
                    Text { text: "\u2715"; color: "#576574"; font.pixelSize: 14; TapHandler { onTapped: toast.hide() } }
                }

                RowLayout {
                    Layout.fillWidth: true; spacing: 6
                    Text {
                        text: root.shotPath ? root.shotPath.replace(root._home, "~") : ""
                        color: "#576574"; font.pixelSize: 10
                        elide: Text.ElideMiddle; Layout.fillWidth: true
                    }
                    Text { text: root.shotTs; color: "#576574"; font.pixelSize: 10 }
                }

                RowLayout {
                    Layout.fillWidth: true; spacing: 6
                    Repeater {
                        model: [
                            { label: "\uD83D\uDCCB Copy",   action: function() { Quickshell.execDetached(["wl-copy", root.shotPath]); toast.hide(); } },
                            { label: "\uD83D\uDCC2 Open",   action: function() { Quickshell.execDetached(["xdg-open", root.shotPath]); toast.hide(); } },
                            { label: "\uD83D\uDDD1  Dismiss", action: function() { toast.hide(); } }
                        ]
                        delegate: Rectangle {
                            Layout.preferredWidth: btnText.implicitWidth + 20
                            Layout.preferredHeight: 28; radius: 6
                            color: hh.hovered ? Qt.rgba(0.30, 0.35, 0.50, 0.30) : Qt.rgba(0.18, 0.22, 0.30, 0.40)
                            border.width: 1; border.color: Qt.rgba(0.35, 0.40, 0.50, 0.20)
                            Text { id: btnText; anchors.centerIn: parent; text: modelData.label; color: "#A0B4CC"; font.pixelSize: 11; font.weight: Font.Medium }
                            HoverHandler { id: hh }
                            TapHandler { onTapped: modelData.action() }
                        }
                    }
                }
            }
        }
    }
}
