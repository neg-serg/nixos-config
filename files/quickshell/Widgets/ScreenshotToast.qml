import QtQuick 2.15
import QtQuick.Layouts 1.15
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import qs.Components

// ScreenshotToast — screenshot feedback card with large preview, dunst-matched style.

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
        onFileChanged: { root.loadAndShow(); reload(); }
    }

    property string shotPath: ""
    property int shotW: 0
    property int shotH: 0
    property string shotSizeHr: ""
    property string shotDepth: ""
    property string shotTs: ""

    // External hide signal (shell.qml sets this on M4+space).
    // Direct visible=false: the slide-based hide() could be interrupted and
    // left the layer mapped (observed 2026-08-08).
    property bool hideRequested: false
    onHideRequestedChanged: {
        if (root.hideRequested) {
            root.hideRequested = false;
            toast.visible = false;
            toast._hiding = false;
        }
    }

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

    // ── Toast window ─────────────────────────────────────────────────
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

        implicitWidth: 460
        implicitHeight: 520

        property int autoHideMs: 8000
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
            radius: 4
            border.width: 1
            color: Qt.rgba(0, 0, 0, 0.85)
            transform: Translate { y: toast.slideY }

            HoverHandler {
                onActiveChanged: { if (active) autoHide.stop(); else autoHide.restart(); }
            }

            ColumnLayout {
                anchors.fill: parent; anchors.margins: 16; spacing: 10

                // ── Large preview ───────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 280
                    radius: 4
                    color: "#181C24"
                    border.width: 1
                    border.color: "#3B4C5C"

                    Image {
                        anchors.fill: parent; anchors.margins: 3
                        source: root.shotPath ? "file://" + root.shotPath : ""
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        cache: false
                        visible: root.shotPath !== ""
                    }
                    MaterialIcon {
                        anchors.centerIn: parent
                        icon: "photo_camera"
                        size: 44
                        color: "#6B718A"
                        visible: root.shotPath === ""
                    }
                    // Click preview to open
                    TapHandler {
                        onTapped: {
                            Quickshell.execDetached(["xdg-open", root.shotPath]);
                            toast.hide();
                        }
                    }
                }

                // ── Title row ───────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true; spacing: 8

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text {
                            text: "Screenshot captured"
                            font.family: "Iosevka"; font.weight: Font.Medium; font.pointSize: 14
                            color: "#BFCAD0"
                        }
                        Text {
                            text: root.shotW + "\u202F\u00D7\u202F" + root.shotH
                                 + "  \u00B7  " + root.shotSizeHr
                                 + (root.shotDepth !== "" ? "  \u00B7  " + root.shotDepth : "")
                            font.family: "Iosevka"; font.pointSize: 12
                            color: "#AEB9C8"
                        }
                    }

                    MaterialIcon {
                        icon: "close"
                        size: 14
                        color: "#6B718A"
                        TapHandler { onTapped: toast.hide() }
                    }
                }

                // ── Path row ────────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true; spacing: 6
                    Text {
                        text: root.shotPath ? root.shotPath.replace(root._home, "~") : ""
                        font.family: "Iosevka"; font.pointSize: 11
                        color: "#6B718A"
                        elide: Text.ElideMiddle; Layout.fillWidth: true
                    }
                    Text {
                        text: root.shotTs
                        font.family: "Iosevka"; font.pointSize: 11
                        color: "#6B718A"
                    }
                }

                // ── OCR actions ─────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true; spacing: 6
                    Repeater {
                        model: [
                            { icon: "text_fields",  label: "OCR",   action: function() { Quickshell.execDetached([root._home + "/.local/bin/pic-ocr", "--engine=tesseract", root.shotPath]); toast.hide(); } },
                            { icon: "auto_awesome", label: "OCR NN", action: function() { Quickshell.execDetached([root._home + "/.local/bin/pic-ocr", "--engine=nn", root.shotPath]); toast.hide(); } }
                        ]
                        delegate: Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 36; radius: 6
                            color: hh.hovered ? "#242A35" : "#181C24"
                            border.width: 1; border.color: "#3B4C5C"
                            RowLayout {
                                id: btnRow
                                anchors.centerIn: parent
                                spacing: 5
                                MaterialIcon {
                                    icon: modelData.icon
                                    size: 14
                                    color: "#BFCAD0"
                                }
                                Text {
                                    text: modelData.label
                                    font.family: "Iosevka"; font.weight: Font.Medium; font.pointSize: 12
                                    color: "#BFCAD0"
                                }
                            }
                            HoverHandler { id: hh }
                            TapHandler { onTapped: modelData.action() }
                        }
                    }
                }

                // ── Actions ─────────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true; spacing: 6
                    Repeater {
                        model: [
                            { icon: "content_copy", label: "Copy",     action: function() { Quickshell.execDetached(["wl-copy", root.shotPath]); toast.hide(); } },
                            { icon: "folder_open",  label: "Open",     action: function() { Quickshell.execDetached(["xdg-open", root.shotPath]); toast.hide(); } },
                            { icon: "delete",       label: "Dismiss",  action: function() { toast.hide(); } }
                        ]
                        delegate: Rectangle {
                            Layout.preferredWidth: btnRow.implicitWidth + 20
                            Layout.preferredHeight: 36; radius: 6
                            color: hh.hovered ? "#242A35" : "#181C24"
                            border.width: 1; border.color: "#3B4C5C"
                            RowLayout {
                                id: btnRow
                                anchors.centerIn: parent
                                spacing: 5
                                MaterialIcon {
                                    icon: modelData.icon
                                    size: 14
                                    color: "#BFCAD0"
                                }
                                Text {
                                    text: modelData.label
                                    font.family: "Iosevka"; font.weight: Font.Medium; font.pointSize: 12
                                    color: "#BFCAD0"
                                }
                            }
                            HoverHandler { id: hh }
                            TapHandler { onTapped: modelData.action() }
                        }
                    }
                }
            }
        }
    }
}
