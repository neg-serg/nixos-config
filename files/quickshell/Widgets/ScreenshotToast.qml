import QtQuick 2.15
import QtQuick.Layouts 1.15
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
/*!
 * ScreenshotToast — macOS-style floating screenshot feedback card.
 * Watches ~/.cache/quickshell/screenshot-event for JSON metadata
 * written by pic-notify. Shows dimensions, size, format, thumbnail,
 * and auto-dismisses after a configurable timeout.
 */
Item {
    id: root
    visible: false

    // ── Trigger file (written by pic-notify) ─────────────────────────────
    readonly property string _eventPath: {
        var home = Quickshell.env("HOME") || "/tmp";
        return home + "/.cache/quickshell/screenshot-event.json";
    }

    FileView {
        id: eventWatcher
        path: root._eventPath
        watchChanges: true
        onFileChanged: {
            root.loadAndShow();
            reload(); // reset watch for next event
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
        try {
            var raw = Quickshell.readFileText(root._eventPath);
            var data = JSON.parse(raw);
            root.shotPath   = data.path   || "";
            root.shotW      = data.w      || 0;
            root.shotH      = data.h      || 0;
            root.shotSizeHr = data.sizeHr || "";
            root.shotDepth  = data.depth  || "";
            root.shotTs     = data.ts     || "";
            toast.show();
        } catch (e) {
            // malformed JSON — ignore
        }
    }

    // ── Toast window (overlay layer for compositor blur) ─────────────────
    PanelWindow {
        id: toast
        color: "transparent"
        visible: false

        WlrLayershell.namespace: "qs-screenshot"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusionMode: ExclusionMode.Ignore

        // Bottom-right corner
        anchors.right: true
        anchors.bottom: true
        WlrLayershell.margins {
            right: 24
            bottom: 24
        }

        // Fixed size — card-style
        implicitWidth: 360
        implicitHeight: 160

        // ── Auto-hide timer ──────────────────────────────────────────────
        property int autoHideMs: 5000
        Timer {
            id: autoHide
            interval: toast.autoHideMs
            repeat: false
            onTriggered: toast.hide()
        }

        function show() {
            slide.stop()
            _hiding = false
            visible = true
            slide.from = 40  // start slightly below
            slide.to   = 0
            slide.start()
            autoHide.restart()
        }

        function hide() {
            slide.stop()
            _hiding = true
            slide.from = slideY
            slide.to   = 40
            slide.start()
        }

        // ── Slide animation ───────────────────────────────────────────────
        property real slideY: 40
        property bool _hiding: false
        NumberAnimation {
            id: slide
            target: toast
            property: "slideY"
            duration: 200
            easing.type: Easing.OutCubic
            onStopped: {
                if (toast._hiding) {
                    toast.visible = false
                    toast._hiding = false
                }
            }
        }

        // ── Card content ──────────────────────────────────────────────────
        Rectangle {
            anchors.fill: parent
            radius: 12
            color: Qt.rgba(0.11, 0.11, 0.16, 0.92)
            border.width: 1
            border.color: Qt.rgba(0.30, 0.35, 0.45, 0.30)

            transform: Translate { y: toast.slideY }

            // Pause auto-hide on hover
            HoverHandler {
                onActiveChanged: {
                    if (active) autoHide.stop()
                    else autoHide.restart()
                }
            }

            // Click to dismiss (or open file)
            TapHandler {
                onTapped: {
                    Quickshell.execDetached(["xdg-open", root.shotPath])
                    toast.hide()
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 8

                // ── Header row: 📸 + dimensions ──────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    // Thumbnail placeholder (actual image if available)
                    Rectangle {
                        Layout.preferredWidth: 56
                        Layout.preferredHeight: 42
                        radius: 8
                        color: Qt.rgba(0.18, 0.18, 0.26, 0.60)
                        border.width: 1
                        border.color: Qt.rgba(0.35, 0.40, 0.50, 0.25)

                        Image {
                            anchors.fill: parent
                            anchors.margins: 2
                            source: root.shotPath ? "file://" + root.shotPath : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            visible: root.shotPath !== ""
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "📸"
                            font.pixelSize: 20
                            visible: root.shotPath === ""
                        }
                    }

                    ColumnLayout {
                        spacing: 2

                        Text {
                            text: "Screenshot captured"
                            color: "#C8D6E5"
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }

                        Text {
                            text: root.shotW + " × " + root.shotH
                                 + "  ·  " + root.shotSizeHr
                                 + (root.shotDepth !== "" ? "  ·  " + root.shotDepth : "")
                            color: "#8395A7"
                            font.pixelSize: 11
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Close button
                    Text {
                        text: "✕"
                        color: "#576574"
                        font.pixelSize: 14
                        TapHandler {
                            onTapped: toast.hide()
                        }
                    }
                }

                // ── Footer: path + timestamp ──────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        text: root.shotPath ? root.shotPath.replace(
                            Quickshell.env("HOME") || "/home", "~"
                        ) : ""
                        color: "#576574"
                        font.pixelSize: 10
                        elide: Text.ElideMiddle
                        Layout.fillWidth: true
                    }

                    Text {
                        text: root.shotTs
                        color: "#576574"
                        font.pixelSize: 10
                    }
                }

                // ── Action buttons ────────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: [
                            { label: "📋 Copy",   action: function() {
                                Quickshell.execDetached(["wl-copy", root.shotPath])
                                toast.hide()
                            }},
                            { label: "📂 Open",   action: function() {
                                Quickshell.execDetached(["xdg-open", root.shotPath])
                                toast.hide()
                            }},
                            { label: "🗑  Dismiss", action: function() { toast.hide() }}
                        ]
                        delegate: Rectangle {
                            Layout.preferredWidth: btnText.implicitWidth + 20
                            Layout.preferredHeight: 28
                            radius: 6
                            color: hoverHnd.hovered
                                   ? Qt.rgba(0.30, 0.35, 0.50, 0.30)
                                   : Qt.rgba(0.18, 0.22, 0.30, 0.40)
                            border.width: 1
                            border.color: Qt.rgba(0.35, 0.40, 0.50, 0.20)

                            Text {
                                id: btnText
                                anchors.centerIn: parent
                                text: modelData.label
                                color: "#A0B4CC"
                                font.pixelSize: 11
                                font.weight: Font.Medium
                            }

                            HoverHandler { id: hoverHnd }
                            TapHandler { onTapped: modelData.action() }
                        }
                    }
                }
            }
        }
    }
}
