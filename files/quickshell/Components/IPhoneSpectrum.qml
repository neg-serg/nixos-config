import QtQuick
import qs.Settings
import "../Helpers/Utils.js" as Utils

// iPhone-style audio spectrum — thin neon bars with an optional glow,
// plus warm analog presets. Bars can be mirrored (centered) or one-sided
// (bottom-anchored). Inspired by iOS Dynamic Island / Now Playing visualizer.
Item {
    id: root
    clip: true

    // ── Input (0..1 values from CAVA) ──
    property var values: []
    // ── Target bar count (downsampled from CAVA's 86) ──
    property int targetBars: 26
    // ── Coloring: accent-driven gradient (used when style is empty) ──
    property color accentColor: Theme.accentPrimary
    property color gradientEnd: Qt.lighter(accentColor, 1.4)
    property real fillOpacity: 0.75
    // Mirror bars above and below the center line; when false, draw a
    // single bottom-anchored bar per bucket.
    property bool mirror: true
    // ── Bar shape (used when style is empty) ──
    property real barGap: 1       // tight spacing, iPhone look
    property real minBarWidth: 2  // thin bars
    // ── Animation ──
    property int animDurationMs: 80

    // Preset style. Empty = use the granular colour/shape properties above.
    // Named presets override colour, thickness, opacity and glow.
    property string style: ""
    // Granular neon glow (used when style is empty).
    property bool glow: false
    property real glowOpacity: 0.35
    property real glowSpread: 2.0

    // Frequency band: bars map linearly across spectrumMinHz..spectrumMaxHz;
    // bars inside colorMinHz..colorMaxHz use the neon/accent colour, the rest
    // render as a dim neutral so only the selected band pops.
    property real spectrumMinHz: (Settings.settings.spectrumMinHz !== undefined) ? Settings.settings.spectrumMinHz : 15
    property real spectrumMaxHz: (Settings.settings.spectrumMaxHz !== undefined) ? Settings.settings.spectrumMaxHz : 24000
    property real colorMinHz: (Settings.settings.spectrumColorMinHz !== undefined) ? Settings.settings.spectrumColorMinHz : 15
    property real colorMaxHz: (Settings.settings.spectrumColorMaxHz !== undefined) ? Settings.settings.spectrumColorMaxHz : 24000
    property color dimColor: "#ffffff"
    property real dimOpacity: (Settings.settings.spectrumDimOpacity !== undefined) ? Settings.settings.spectrumDimOpacity : 0.18

    function _preset() {
        switch (root.style) {
            case "neon-violet":
                return {
                    base: Qt.rgba(0.42, 0.0, 1.0, 1),
                    end: Qt.rgba(1.0, 0.43, 1.0, 1),
                    minBarWidth: 1,
                    barGap: 2,
                    fillOpacity: 0.45,
                    glowOpacity: 0.55,
                    glowSpread: 2.4
                };
            case "analog-amber":
                return {
                    base: Qt.rgba(1.0, 0.56, 0.0, 1),
                    end: Qt.rgba(1.0, 0.82, 0.5, 1),
                    minBarWidth: 2,
                    barGap: 2,
                    fillOpacity: 0.65,
                    glowOpacity: 0.3,
                    glowSpread: 1.9
                };
            case "analog-rose":
                return {
                    base: Qt.rgba(0.85, 0.11, 0.38, 1),
                    end: Qt.rgba(1.0, 0.5, 0.65, 1),
                    minBarWidth: 2,
                    barGap: 3,
                    fillOpacity: 0.6,
                    glowOpacity: 0.35,
                    glowSpread: 2.1
                };
            case "neon-cyan":
            default:
                return {
                    base: Qt.rgba(0.0, 0.9, 1.0, 1),
                    end: Qt.rgba(0.52, 1.0, 1.0, 1),
                    minBarWidth: 1,
                    barGap: 1,
                    fillOpacity: 0.5,
                    glowOpacity: 0.5,
                    glowSpread: 2.6
                };
        }
    }

    readonly property var _presetCfg: root.style ? root._preset() : null
    readonly property color _barBase: root._presetCfg ? root._presetCfg.base : root.accentColor
    readonly property color _barEnd: root._presetCfg ? root._presetCfg.end : root.gradientEnd
    readonly property real _barGap: root._presetCfg ? root._presetCfg.barGap : root.barGap
    readonly property real _barMinWidth: root._presetCfg ? root._presetCfg.minBarWidth : root.minBarWidth
    readonly property real _barFillOpacity: root._presetCfg ? root._presetCfg.fillOpacity : root.fillOpacity
    readonly property bool _glowEnabled: root._presetCfg ? true : root.glow
    readonly property real _glowOpacity: root._presetCfg ? root._presetCfg.glowOpacity : root.glowOpacity
    readonly property real _glowSpread: root._presetCfg ? root._presetCfg.glowSpread : root.glowSpread

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
    function gradientAt(i, alpha) {
        var base = root._barBase;
        var end = root._barEnd;
        if (root.barCount <= 1) return Qt.rgba(base.r, base.g, base.b, alpha);
        var t = i / (root.barCount - 1);
        return Qt.rgba(
            root.lerp(base.r, end.r, t),
            root.lerp(base.g, end.g, t),
            root.lerp(base.b, end.b, t),
            alpha
        );
    }
    // Linear frequency for bar index i across the configured full scale.
    function freqAt(i) {
        var n = Math.max(1, root.barCount);
        var t = (n <= 1) ? 0 : (i / (n - 1));
        return root.spectrumMinHz + t * (root.spectrumMaxHz - root.spectrumMinHz);
    }
    function dimColorAt(alpha) {
        var c = root.dimColor;
        return Qt.rgba(c.r, c.g, c.b, alpha);
    }

    readonly property real barW: {
        var n = Math.max(1, root.barCount);
        var w = (root.width - (n - 1) * root._barGap) / n;
        return Math.max(root._barMinWidth, w);
    }

    Repeater {
        model: root.barCount
        delegate: Item {
            width: root.barW
            height: parent.height
            x: index * (root.barW + root._barGap)

            property real v: Utils.clamp01((root._downsampled[index] || 0))
            // Skip bars with no signal so silence does not leave 1px stubs.
            readonly property bool barVisible: v > 0.001
            // Only the selected frequency band is coloured; the rest is dim.
            readonly property bool inColorBand: {
                var f = root.freqAt(index);
                return f >= root.colorMinHz && f <= root.colorMaxHz;
            }
            property color barColor: parent.inColorBand
                ? root.gradientAt(index, root._barFillOpacity)
                : root.dimColorAt(root.dimOpacity)
            property color glowColor: root.gradientAt(index, root._glowOpacity)

            // Neon halo behind the bottom core bar (coloured band only).
            Rectangle {
                visible: parent.barVisible && root._glowEnabled && parent.inColorBand
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width * root._glowSpread
                radius: width / 2
                height: root.mirror
                    ? (parent.v * root.halfH)
                    : (parent.v * root.height)
                y: root.mirror ? root.halfH : root.height - height
                color: parent.glowColor
                Behavior on height {
                    enabled: Theme.animationsEnabled
                    SmoothedAnimation { duration: root.animDurationMs }
                }
            }

            // Bottom bar: grows upward from the bottom when one-sided,
            // or downward from the vertical center when mirrored.
            Rectangle {
                visible: parent.barVisible
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width
                radius: width / 2
                height: root.mirror
                    ? (parent.v * root.halfH)
                    : (parent.v * root.height)
                y: root.mirror ? root.halfH : root.height - height
                color: parent.barColor
                Behavior on height {
                    enabled: Theme.animationsEnabled
                    SmoothedAnimation { duration: root.animDurationMs }
                }
            }

            // Neon halo behind the top bar (mirrored, coloured band only).
            Rectangle {
                visible: root.mirror && parent.barVisible && root._glowEnabled && parent.inColorBand
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width * root._glowSpread
                radius: width / 2
                height: parent.v * root.halfH
                y: root.halfH - height
                color: parent.glowColor
                Behavior on height {
                    enabled: Theme.animationsEnabled
                    SmoothedAnimation { duration: root.animDurationMs }
                }
            }

            // Top bar: rendered only when mirrored.
            Rectangle {
                visible: root.mirror && parent.barVisible
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width
                radius: width / 2
                height: parent.v * root.halfH
                y: root.halfH - height
                color: parent.barColor
                Behavior on height {
                    enabled: Theme.animationsEnabled
                    SmoothedAnimation { duration: root.animDurationMs }
                }
            }
        }
    }
}
