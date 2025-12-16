import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.Settings
import qs.Services as Services
import qs.Components
import qs.Services
import "../../Helpers/Utils.js" as Utils

WidgetCapsule {
    id: root
    property bool enabled: false
    property int fallbackIntervalMs:Theme.mpdFlagsFallbackMs
    property color iconColor: Theme.textPrimary
    property int iconPx: Math.round(Theme.fontSizeSmall * capsuleScale)
    property string cmd: "(mpc status || rmpc status)"
    property var activeFlags: [] // [{ key, icon, title }]
    property string mpdState: "unknown" // playing | paused | stopped | unknown
    visible: enabled && activeFlags.length > 0
    backgroundKey: "mpdFlags"

    function parseStatus(text) {
        try {
            const s = String(text || "");
            var trimmed = s.trim();
            const flags = [];
            function pushFlag(ok, key, icon, title) { if (ok) flags.push({ key, icon, title }); }
            function isOn(v) {
                var t = String(v).toLowerCase();
                return t === "on" || t === "1" || t === "true" || t === "one";
            }
            if (trimmed.startsWith("{") || trimmed.startsWith("[")) {
                var obj = JSON.parse(trimmed);
                var stv = (obj.state || obj.State || "").toString().toLowerCase();
                if (!stv && obj.mpd && obj.mpd.state) stv = String(obj.mpd.state).toLowerCase();
                mpdState = stv || "unknown";
                pushFlag(!!obj.repeat, "repeat", "repeat", "Repeat");
                pushFlag(!!obj.random, "random", "shuffle", "Random");
                var sglv = (obj.single !== undefined) ? obj.single : (obj.options && obj.options.single);
                pushFlag(isOn(sglv), "single", "repeat_one", "Single");
                var conv = (obj.consume !== undefined) ? obj.consume : (obj.options && obj.options.consume);
                pushFlag(isOn(conv), "consume", "auto_delete", "Consume");
                var xf = (obj.xfade !== undefined && obj.xfade !== null) ? obj.xfade : (obj.options && obj.options.xfade);
                var xfOn = false;
                if (typeof xf === 'number') xfOn = xf > 0; else if (xf !== undefined && xf !== null) xfOn = !/^0$|^off$/i.test(String(xf));
                pushFlag(xfOn, "xfade", "blur_linear", "Crossfade");
            } else {
                var st = "unknown";
                var mbr = trimmed.match(/\[(playing|paused|stopped)\]/i);
                if (mbr && mbr[1]) st = String(mbr[1]).toLowerCase();
                var mst = trimmed.match(/\bstate:\s*(playing|paused|stopped)\b/i);
                if (mst && mst[1]) st = String(mst[1]).toLowerCase();
                mpdState = st;
                const rep = /\brepeat:\s*(on|off|1|0)\b/i.exec(trimmed);
                const rnd = /\brandom:\s*(on|off|1|0)\b/i.exec(trimmed);
                const sgl = /\bsingle:\s*(on|off|1|0)\b/i.exec(trimmed);
                const con = /\bconsume:\s*(on|off|1|0)\b/i.exec(trimmed);
                const xfd = /\b(?:xfade|crossfade):\s*([0-9]+|on|off)\b/i.exec(trimmed);
                pushFlag(rep && isOn(rep[1]), "repeat", "repeat", "Repeat");
                pushFlag(rnd && isOn(rnd[1]), "random", "shuffle", "Random");
                pushFlag(sgl && isOn(sgl[1]), "single", "repeat_one", "Single");
                pushFlag(con && isOn(con[1]), "consume", "auto_delete", "Consume");
                pushFlag(xfd && !/^0$|^off$/i.test(xfd[1]), "xfade", "blur_linear", "Crossfade");
            }
            activeFlags = flags;
        } catch (e) {
            activeFlags = [];
        }
    }

    function refresh() {
        try {
            if (!proc.running) proc.running = true
        } catch (e) { }
    }

    function isMpd() {
        try {
            const p = MusicManager.currentPlayer;
            if (!p) return false;
            const n = String(p.identity || p.name || p.id || "").toLowerCase();
            return /(mpd|mpdris)/.test(n);
        } catch (e) { return false; }
    }

    // One-shot status parser
    ProcessRunner {
        id: proc
        cmd: ["bash", "-lc", root.cmd + " 2>/dev/null || true"]
        autoStart: false
        restartOnExit: false
        // Consume entire output via onLine accumulation; sufficient for our parser
        property string _buf: ""
        onLine: (s) => { _buf += (s + "\n") }
        onExited: (code, status) => { root.parseStatus(_buf); _buf = "" }
    }

    // Updates via MPD idle on 'options' subsystem
    ProcessRunner {
        id: idle
        // Prefer mpc; fallback to rmpc
        cmd: ["bash", "-lc", "mpc -q idle options player 2>/dev/null || rmpc -q idle options player 2>/dev/null || true"]
        restartOnExit: true
        backoffMs: 250
        onExited: (code, status) => {
            if (root.enabled) proc.start()
        }
    }

    // Fallback polling if idle misses or unsupported (centralized timer)
    Connections {
        target: Services.Timers
        function onTickMpdFlagsFallback() {
            if (root.enabled) root.refresh();
        }
    }

    // Control lifecycle
    Component.onCompleted: { if (enabled) { proc.start(); idle.start(); } }
    onEnabledChanged: {
        if (enabled) {
            activeFlags = [];
            proc.start();
            idle.start();
        } else {
            idle.stop();
            activeFlags = [];
        }
    }

    // Icon row
    Row {
        id: content
        spacing: Math.round(Theme.panelRowSpacingSmall * capsuleScale)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        clip: true
        Repeater {
            model: activeFlags
            delegate: MaterialIcon {
                icon: modelData.icon
                color: root.iconColor
                size: root.iconPx
                opacity: Theme.uiIconEmphasisOpacity
            }
        }
    }

    implicitWidth: horizontalPadding * 2 + content.implicitWidth
    implicitHeight: forceHeightFromMetrics
        ? Math.max(capsuleMetrics.height, content.implicitHeight + verticalPadding * 2)
        : content.implicitHeight + verticalPadding * 2
}
