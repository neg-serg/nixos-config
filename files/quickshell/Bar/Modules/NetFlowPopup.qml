import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Components
import qs.Settings
import "../../Helpers/Color.js" as Color
import "../../Helpers/Format.js" as Format

/*!
 * NetFlowPopup — "flow" dashboard popup.
 *
 * Streams `flow -json-stream` (the flow TUI data engine, ~10 Hz) and renders
 * live down/up throughput: big readouts, a rolling history area chart with a
 * moving sheen, peak glow dots and a LIVE pulse. History = last 600 samples
 * (60 s window).
 */
PanelOverlaySurface {
    id: root

    // flow binary: pinned via FLOW_BIN (module) or resolved from the service PATH
    readonly property string flowBin: Quickshell.env("FLOW_BIN") || "flow"
    readonly property int historyLen: 600

    property real downBps: 0
    property real upBps: 0
    property string downHuman: "0 B/s"
    property string upHuman: "0 B/s"
    property string ifaceName: "—"
    property real peakDown: 0
    property real peakUp: 0
    property bool running: false
    property var downHistory: []
    property var upHistory: []
    // Capsule's on-screen x; the popup opens bottom-left, aligned with it.
    property real triggerX: 0
    // First-open latch: the flow stream stays alive across open/close.
    property bool _procStarted: false

    readonly property bool _active: downBps > 1 || upBps > 1
    readonly property real _s: Theme.scale(screen) > 0 ? Theme.scale(screen) : 1.0

    // flow's own palette: download blue→cyan, upload green→lime
    readonly property color _downA: "#3B82F6"
    readonly property color _downB: "#00F5D4"
    readonly property color _upA: "#10B981"
    readonly property color _upB: "#A3E635"

    backgroundColor: Color.withAlpha(Theme.surface, 0.92)
    borderColor: "transparent"
    borderWidth: 0
    width: Math.round(470 * root._s)
    height: Math.round(338 * root._s)
    // Bottom-left, just above the bar, left-aligned with the network capsule.
    anchors {
        left: parent.left
        bottom: parent.bottom
        leftMargin: Math.max(4 * root._s, root.triggerX)
        bottomMargin: Math.round(36 * root._s)
    }

    // ── data engine: flow -json-stream ──────────────────────────────
    ProcessRunner {
        id: flowProc
        cmd: [root.flowBin, "-json-stream"]
        jsonLine: true
        restartMode: "always"
        backoffMs: 1000
        autoStart: false
        onJson: (o) => root._onSample(o)
    }

    Timer {
        id: repaint
        interval: 100
        repeat: true
        running: root.running
        onTriggered: { if (chart.visible) chart.requestPaint(); }
    }

    function start() {
        // Keep the history/peaks across open/close — only the flow stream is
        // (re)started once; samples keep appending while the popup is closed.
        root.running = true;
        if (!root._procStarted) {
            root._procStarted = true;
            flowProc.start();
        }
    }

    function stop() {
        root.running = false;
        // flowProc intentionally stays alive so data is not lost on close.
    }

    function _onSample(o) {
        root.downBps = Number(o.download_bps) || 0;
        root.upBps = Number(o.upload_bps) || 0;
        root.downHuman = o.download_human || root._fmtFull(root.downBps);
        root.upHuman = o.upload_human || root._fmtFull(root.upBps);
        if (o.interface) root.ifaceName = o.interface;
        root.peakDown = Math.max(root.peakDown, root.downBps);
        root.peakUp = Math.max(root.peakUp, root.upBps);
        const d = root.downHistory.slice();
        const u = root.upHistory.slice();
        d.push(root.downBps);
        u.push(root.upBps);
        if (d.length > root.historyLen) { d.shift(); u.shift(); }
        root.downHistory = d;
        root.upHistory = u;
    }

    // "1.24 MB/s" full format
    function _fmtFull(v) {
        if (v >= 1e9) return (v / 1e9).toFixed(2) + " GB/s";
        if (v >= 1e6) return (v / 1e6).toFixed(2) + " MB/s";
        if (v >= 1e3) return (v / 1e3).toFixed(1) + " KB/s";
        return Math.round(v) + " B/s";
    }

    // "1.2M" compact format for axis labels
    function _fmtCompact(v) {
        if (v >= 1e9) return (v / 1e9).toFixed(1) + "G";
        if (v >= 1e6) return (v / 1e6).toFixed(1) + "M";
        if (v >= 1e3) return (v / 1e3).toFixed(0) + "K";
        return Math.round(v) + "";
    }

    function _paintChart(ctx) {
        const W = chart.width;
        const H = chart.height;
        ctx.clearRect(0, 0, W, H);

        const d = root.downHistory;
        const u = root.upHistory;
        const n = Math.max(d.length, u.length);
        const pad = 5;

        if (n < 2) {
            ctx.fillStyle = Format.colorCss(Theme.textDisabled);
            ctx.font = (11 * root._s) + "px " + Theme.fontFamily;
            ctx.textAlign = "center";
            ctx.fillText("waiting for flow…", W / 2, H / 2);
            return;
        }

        let maxV = 1;
        for (let i = 0; i < n; i++) { maxV = Math.max(maxV, d[i], u[i]); }
        const yMax = Math.max(1, maxV * 1.15);
        const plotW = W - 2 * pad;
        const plotH = H - 2 * pad;
        const xAt = (i) => pad + (n === 1 ? 0 : i / (n - 1)) * plotW;
        const yAt = (v) => pad + plotH - (v / yMax) * plotH;

        // horizontal grid + axis labels
        ctx.strokeStyle = Format.colorCss(Color.withAlpha(Theme.textDisabled, 0.18));
        ctx.lineWidth = 1;
        ctx.font = (9 * root._s) + "px " + Theme.fontFamily;
        for (let g = 0; g <= 3; g++) {
            const frac = g / 3;
            const y = pad + plotH - frac * plotH;
            ctx.beginPath();
            ctx.moveTo(pad, y);
            ctx.lineTo(W - pad, y);
            ctx.stroke();
            ctx.fillStyle = Format.colorCss(Theme.textDisabled);
            ctx.textAlign = "left";
            ctx.fillText(root._fmtCompact(yMax * frac), W - pad + 5, y + 3);
        }

        function drawSeries(arr, colorA, colorB, lineW) {
            if (arr.length < 2) return;
            // filled area
            const grad = ctx.createLinearGradient(0, pad, 0, pad + plotH);
            grad.addColorStop(0, Format.colorCss(colorA, 0.10));
            grad.addColorStop(1, Format.colorCss(colorB, 0.28));
            ctx.beginPath();
            ctx.moveTo(xAt(0), yAt(arr[0]));
            for (let i = 1; i < arr.length; i++) ctx.lineTo(xAt(i), yAt(arr[i]));
            ctx.lineTo(xAt(arr.length - 1), pad + plotH);
            ctx.lineTo(xAt(0), pad + plotH);
            ctx.closePath();
            ctx.fillStyle = grad;
            ctx.fill();
            // line
            const lineGrad = ctx.createLinearGradient(0, 0, W, 0);
            lineGrad.addColorStop(0, Format.colorCss(colorA));
            lineGrad.addColorStop(1, Format.colorCss(colorB));
            ctx.beginPath();
            ctx.moveTo(xAt(0), yAt(arr[0]));
            for (let i = 1; i < arr.length; i++) ctx.lineTo(xAt(i), yAt(arr[i]));
            ctx.strokeStyle = lineGrad;
            ctx.lineWidth = lineW;
            ctx.lineJoin = "round";
            ctx.lineCap = "round";
            ctx.stroke();
        }

        drawSeries(u, root._upA, root._upB, 1.4); // TX behind
        drawSeries(d, root._downA, root._downB, 2.0); // RX on top

        // glow dot at the latest sample
        if (d.length > 0) {
            const lx = xAt(d.length - 1);
            const ly = yAt(d[d.length - 1]);
            ctx.shadowBlur = 10;
            ctx.shadowColor = Format.colorCss(root._downB, 0.8);
            ctx.beginPath();
            ctx.arc(lx, ly, 3, 0, Math.PI * 2);
            ctx.fillStyle = Format.colorCss(root._downB);
            ctx.fill();
            ctx.shadowBlur = 0;
        }

        // moving sheen sweep
        const t = (Date.now() / 4000) % 1;
        const sx = pad + t * plotW;
        const sheenW = 48 * root._s;
        const sheen = ctx.createLinearGradient(sx - sheenW / 2, 0, sx + sheenW / 2, 0);
        sheen.addColorStop(0, "rgba(255,255,255,0)");
        sheen.addColorStop(0.5, "rgba(255,255,255,0.05)");
        sheen.addColorStop(1, "rgba(255,255,255,0)");
        ctx.fillStyle = sheen;
        ctx.fillRect(sx - sheenW / 2, pad, sheenW, plotH);
    }

    // ── UI ───────────────────────────────────────────────────────────
    Column {
        anchors.fill: parent
        anchors.margins: Math.round(14 * root._s)
        spacing: Math.round(10 * root._s)

        // header: wordmark + interface chip + live status
        RowLayout {
            width: parent.width
            spacing: Math.round(10 * root._s)
            Text {
                text: "flow"
                font.family: Theme.fontFamily
                font.pixelSize: Math.round(17 * root._s)
                font.bold: true
                color: Theme.accentPrimary
            }
            Rectangle {
                height: Math.round(18 * root._s)
                width: ifaceLabel.implicitWidth + Math.round(14 * root._s)
                radius: Math.round(9 * root._s)
                color: Color.withAlpha(Theme.accentPrimary, 0.15)
                border.color: Color.withAlpha(Theme.accentPrimary, 0.35)
                border.width: 1
                Layout.alignment: Qt.AlignVCenter
                Text {
                    id: ifaceLabel
                    anchors.centerIn: parent
                    text: root.ifaceName
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.round(11 * root._s)
                    color: Theme.textSecondary
                }
            }
            Item { Layout.fillWidth: true }
            Rectangle {
                width: Math.round(8 * root._s)
                height: Math.round(8 * root._s)
                radius: width / 2
                color: root._active ? root._downB : Theme.textDisabled
                Layout.alignment: Qt.AlignVCenter
                SequentialAnimation on opacity {
                    running: root.running
                    loops: Animation.Infinite
                    NumberAnimation { from: 1; to: 0.25; duration: 700; easing.type: Easing.InOutQuad }
                    NumberAnimation { from: 0.25; to: 1; duration: 700; easing.type: Easing.InOutQuad }
                }
            }
            Text {
                text: root.running ? (root._active ? "LIVE" : "IDLE") : "OFF"
                font.family: Theme.fontFamily
                font.pixelSize: Math.round(10 * root._s)
                font.bold: true
                color: root._active ? root._downB : Theme.textDisabled
                Layout.alignment: Qt.AlignVCenter
            }
        }

        // big readouts
        Row {
            width: parent.width
            spacing: Math.round(24 * root._s)
            Column {
                width: (parent.width - parent.spacing) / 2
                spacing: Math.round(2 * root._s)
                Text { text: "↓ DOWN"; font.family: Theme.fontFamily; font.pixelSize: Math.round(10 * root._s); font.bold: true; color: Theme.textDisabled }
                Text { text: root.downHuman; font.family: Theme.fontFamily; font.pixelSize: Math.round(20 * root._s); font.bold: true; color: root._downA }
                Text { text: "peak " + root._fmtFull(root.peakDown); font.family: Theme.fontFamily; font.pixelSize: Math.round(10 * root._s); color: Theme.textDisabled }
            }
            Column {
                width: (parent.width - parent.spacing) / 2
                spacing: Math.round(2 * root._s)
                Text { text: "↑ UP"; font.family: Theme.fontFamily; font.pixelSize: Math.round(10 * root._s); font.bold: true; color: Theme.textDisabled }
                Text { text: root.upHuman; font.family: Theme.fontFamily; font.pixelSize: Math.round(20 * root._s); font.bold: true; color: root._upA }
                Text { text: "peak " + root._fmtFull(root.peakUp); font.family: Theme.fontFamily; font.pixelSize: Math.round(10 * root._s); color: Theme.textDisabled }
            }
        }

        // history chart
        Rectangle {
            id: chartBg
            width: parent.width
            height: Math.round(140 * root._s)
            radius: Math.round(10 * root._s)
            color: Color.withAlpha(Theme.surfaceVariant, 0.5)
            clip: true
            Canvas {
                id: chart
                anchors.fill: parent
                onPaint: {
                    var ctx = chart.getContext("2d");
                    root._paintChart(ctx);
                }
            }
        }

        // footer
        Text {
            text: "flow — see your network breathe   ·   ~10 Hz   ·   " + Math.round(root.historyLen / 10) + " s window"
            font.family: Theme.fontFamily
            font.pixelSize: Math.round(9.5 * root._s)
            color: Theme.textDisabled
        }
    }
}
