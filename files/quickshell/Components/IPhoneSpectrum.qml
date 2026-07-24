import QtQuick
import qs.Settings
import "../Helpers/Utils.js" as Utils

// iPhone-style audio spectrum — mirrored bars growing from center,
// capsule-shaped, accent-gradient, fluid animation.
// Inspired by iOS Dynamic Island / Now Playing visualizer.
Item {
    id: root
    clip: true

    // ── Input (0..1 values from CAVA) ──
    property var values: []
    // ── Target bar count (downsampled from CAVA's 86) ──
    property int targetBars: 26
    // ── Coloring: accent-driven gradient ──
    property color accentColor: "#006FCC"
    property color gradientEnd: Qt.lighter(accentColor, 1.4)
    property real fillOpacity: 0.75
    // ── Bar shape ──
    property real barGap: 1       // tight spacing, iPhone look
    property real minBarWidth: 2  // thin bars
    // ── Animation ──
    property int animDurationMs: 80

    // Downsampled values
    readonly property var _downsampled: {
        var src = root.values;
        if (!src || src.length === 0) return [];
        var n = root.targetBars;
        if (n >= src.length) return src;
        var out = [];
        var step = src.length / n;
        for (var i = 0; i < n; i++) {
            var s = Math.floor(i * step);
            var e = Math.floor((i + 1) * step);
            if (e <= s) e = s + 1;
            var sum = 0;
            for (var j = s; j < e; j++) sum += (src[j] || 0);
            out.push(sum / (e - s));
        }
        return out;
    }

    readonly property int barCount: _downsampled.length
    readonly property real halfH: height / 2

    function lerp(a, b, t) { return a + (b - a) * t }
    function colorAt(i) {
        if (barCount <= 1) return accentColor;
        var t = i / (barCount - 1);
        return Qt.rgba(
            lerp(accentColor.r, gradientEnd.r, t),
            lerp(accentColor.g, gradientEnd.g, t),
            lerp(accentColor.b, gradientEnd.b, t),
            1
        );
    }

    readonly property real barW: {
        var n = Math.max(1, barCount);
        var w = (width - (n - 1) * barGap) / n;
        return Math.max(minBarWidth, w);
    }

    Repeater {
        model: root.barCount
        delegate: Item {
            width: root.barW
            height: parent.height
            x: index * (root.barW + root.barGap)

            property real v: Utils.clamp01((root._downsampled[index] || 0))

            // Bottom half bar
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width
                radius: width / 2
                height: Math.max(1, parent.v * root.halfH)
                y: root.halfH
                color: {
                    var c = root.colorAt(index);
                    return Qt.rgba(c.r, c.g, c.b, root.fillOpacity);
                }
                Behavior on height {
                    enabled: Theme.animationsEnabled
                    SmoothedAnimation { duration: root.animDurationMs }
                }
            }

            // Top half bar (mirrored)
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width
                radius: width / 2
                height: Math.max(1, parent.v * root.halfH)
                y: root.halfH - height
                color: {
                    var c = root.colorAt(index);
                    return Qt.rgba(c.r, c.g, c.b, root.fillOpacity);
                }
                Behavior on height {
                    enabled: Theme.animationsEnabled
                    SmoothedAnimation { duration: root.animDurationMs }
                }
            }
        }
    }
}
