import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.Components
import qs.Settings
import "../../Helpers/Color.js" as Color

PanelOverlaySurface {

    // Copy journal problems (error/warn entries) to the clipboard when the
    // dashboard opens. Invoked by the capsule's opened() signal — the popup's
    // own `visible` never toggles (the parent overlay window does), so we must
    // not hook onVisibleChanged here. Retries briefly until journal data is
    // collected, and aborts if the dashboard is dismissed first.
    function copyProblemsToClipboard() {
        root._wantCopy = true;
        root._copyAttempts = 0;
        copyRetryTimer.start();
    }

    function cancelPendingCopy() {
        root._wantCopy = false;
        root._copyAttempts = 0;
        copyRetryTimer.stop();
    }

    function _doCopyProblems() {
        var entries = root.logEntries || [];
        var lines = [];
        for (var i = 0; i < entries.length; i++) {
            var e = entries[i];
            if (e.level === "error" || e.level === "warn") {
                lines.push("[" + e.time + "] " + e.service + ": " + e.message);
            }
        }
        if (lines.length > 0) Quickshell.clipboardText = lines.join("\n");
    }

    property bool _wantCopy: false
    property int _copyAttempts: 0
    Timer {
        id: copyRetryTimer
        interval: 200
        repeat: true
        onTriggered: {
            if (!root._wantCopy) { root._copyAttempts = 0; stop(); return; }
            if (root.journalReady && root.logEntries.length > 0) {
                root._wantCopy = false;
                root._copyAttempts = 0;
                stop();
                root._doCopyProblems();
            } else if (++root._copyAttempts > 25) { // ~5s cap, then give up
                root._wantCopy = false;
                root._copyAttempts = 0;
                stop();
            }
        }
    }
    id: root

    backgroundColor: Color.withAlpha(Theme.surface, 0.85)
    borderColor: "transparent"
    borderWidth: 0
    cornerRadiusOverride: Math.round(Theme.cornerRadiusLarge / 3)

    anchors.centerIn: parent
    implicitWidth: Math.round(Math.min(1040, parent.width * 0.92))
    implicitHeight: Math.round(Math.max(480, parent.height - 60))

    Rectangle { anchors.top:parent.top; anchors.left:parent.left; anchors.right:parent.right; height:1; color:Color.withAlpha(Theme.accentPrimary,0.25) }

    readonly property color accentColor: Color.withAlpha(Theme.accentPrimary, 0.85)
    readonly property color accentDim: Color.withAlpha(Theme.accentPrimary, 0.35)
    readonly property color cardBg: Color.withAlpha(Theme.accentPrimary, 0.06)
    readonly property int _iconSz: Math.round(Theme.fontSizeSmall * 1.2) || 18
    readonly property int _fontSize: Math.round(Theme.fontSizeSmall * 1.2) || 14
    readonly property int _fontSizeSmall: Math.round(Theme.fontSizeSmall * 0.95) || 12
    readonly property int _fontSizeMedium: Math.round(Theme.fontSizeMedium * 1.2) || 18
    readonly property real _pad: 14
    readonly property real _spacing: 8
    readonly property real _cardH: 56
    readonly property color sepColor: "transparent"
    readonly property string _ttyLogDir: {
        var home = Quickshell.env("HOME") || "/tmp";
        return home + "/.cache/quickshell/tty-logs";
    }

    property var logEntries: []
    property int totalLogs: 0
    property int errorCount: 0
    property int serviceCount: 0
    property bool journalReady: false
    property var _pendingEntries: []
    property var _pendingServices: ({})
    // TTY log output
    property var ttyOutput: []

    // ── Journal ──
    ProcessRunner {
        id: journalCtl
        cmd: ["/run/current-system/sw/bin/journalctl","--no-pager","-n","120","--output=json","--since","10 minutes ago"]
        autoStart:true; restartOnExit:false
        onLine:(s)=>{root._parseJournalLine(s)}
        onExited:{root._finalizeJournalEntries()}
    }

    // journalctl --output=json serializes any message that contains control
    // bytes (e.g. quickshell's ANSI color codes) as a decimal byte array, like
    // "[27,91,51,50,109,32,32,73,78,70,79,...]". Decode it back into text so
    // the dashboard and the clipboard copy stay readable instead of showing
    // "27,91,51,..." garbage.
    function _decodeJournalMessage(msg) {
        if (!/^\[[0-9,\s]+\]$/.test(msg)) return msg;
        var parts = msg.slice(1, -1).split(",");
        var bytes = [];
        for (var i = 0; i < parts.length; i++) {
            var v = parseInt(parts[i], 10);
            if (isNaN(v) || v < 0 || v > 255) return msg;
            bytes.push(v);
        }
        var out = "";
        var i2 = 0;
        while (i2 < bytes.length) {
            var b = bytes[i2];
            if (b < 0x80) { out += String.fromCharCode(b); i2++; }
            else if (b < 0xe0 && i2 + 1 < bytes.length) { out += String.fromCharCode(((b & 0x1f) << 6) | (bytes[i2 + 1] & 0x3f)); i2 += 2; }
            else if (b < 0xf0 && i2 + 2 < bytes.length) { out += String.fromCharCode(((b & 0x0f) << 12) | ((bytes[i2 + 1] & 0x3f) << 6) | (bytes[i2 + 2] & 0x3f)); i2 += 3; }
            else if (i2 + 3 < bytes.length) { out += String.fromCharCode(((b & 0x07) << 18) | ((bytes[i2 + 1] & 0x3f) << 12) | ((bytes[i2 + 2] & 0x3f) << 6) | (bytes[i2 + 3] & 0x3f)); i2 += 4; }
            else { out += "\ufffd"; i2++; }
        }
        return out;
    }

    function _cleanJournalMessage(msg) {
        var s = root._decodeJournalMessage(msg);
        // Strip ANSI escape sequences (colorized logs) and stray control chars.
        s = s.replace(/\x1b\[[0-9;]*[a-zA-Z]/g, "");
        s = s.replace(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/g, "");
        return s;
    }

    function _parseJournalLine(raw){var s=String(raw).trim();if(!s)return;var obj;try{obj=JSON.parse(s)}catch(e){return}
        var t=obj.__REALTIME_TIMESTAMP||"0";var d=new Date(parseInt(t.substring(0,13),10))
        var ts=("0"+d.getHours()).slice(-2)+":"+("0"+d.getMinutes()).slice(-2)+":"+("0"+d.getSeconds()).slice(-2)
        var id=obj.SYSLOG_IDENTIFIER||obj._SYSTEMD_UNIT||obj._COMM||"?";if(id.length>0)root._pendingServices[id]=true
        var msg=root._cleanJournalMessage(String(obj.MESSAGE||""))
        var p=parseInt(obj.PRIORITY,10);var lv="info"
        if(!isNaN(p)){if(p<=3)lv="error";else if(p===4)lv="warn";else if(p>=7)lv="debug"}
        else{var ml=msg.toLowerCase();if(ml.indexOf("error")>=0||ml.indexOf("fail")>=0||ml.indexOf("fatal")>=0)lv="error";else if(ml.indexOf("warn")>=0)lv="warn";else if(ml.indexOf("debug")>=0)lv="debug"}
        root._pendingEntries.push({time:ts,level:lv,service:id,message:msg.length>200?msg.substring(0,200)+"...":msg})}

    function _finalizeJournalEntries(){if(!root._pendingEntries||root._pendingEntries.length===0)return
        var e=0;for(var i=0;i<root._pendingEntries.length;i++){if(root._pendingEntries[i].level==="error")e++}
        root.logEntries=root._pendingEntries;root.totalLogs=root._pendingEntries.length;root.errorCount=e;root.serviceCount=Object.keys(root._pendingServices).length;root.journalReady=true}

    function refreshAll(){root._pendingEntries=[];root._pendingServices=({});root.journalReady=false;journalCtl.stop();journalCtl.start()}
    Timer{interval:15000;repeat:true;running:true;triggeredOnStart:true;onTriggered:root.refreshAll()}

    Component.onCompleted: { refreshAll() }

    // ── TTY log scanner ──
    ProcessRunner {
        id: ttyScanner
        cmd: ["bash","-c","for f in " + root._ttyLogDir + "/*.log; do [ -f \"$f\" ] || continue; echo \"===TTY===\" \"$(basename \"$f\" .log)\"; tail -n 25 \"$f\" | sed 's/\\x1b\\[[0-9;]*[a-zA-Z]//g'; done"]
        autoStart:false; restartOnExit:false
        onLine:(s)=>{root._parseTtyLine(s)}
        onExited:{root._flushTtySection(); root.ttyOutput = root.ttyOutput}
    }

    property var _pendingTty: []
    property string _currentTtyName: ""
    function _parseTtyLine(raw) {
        var s = String(raw);
        if (s.indexOf("===TTY===") === 0) {
            if (_currentTtyName) root._flushTtySection();
            _currentTtyName = s.substring(10).trim();
            _pendingTty = [];
        } else {
            var trimmed = s.trim();
            if (trimmed) _pendingTty.push(trimmed);
        }
    }
    function _flushTtySection() {
        if (!_currentTtyName) return;
        var existing = root.ttyOutput.find(function(e) { return e.name === root._currentTtyName; });
        if (existing) {
            existing.lines = _pendingTty;
        } else {
            root.ttyOutput.push({name: root._currentTtyName, lines: _pendingTty});
        }
        _currentTtyName = "";
        _pendingTty = [];
    }

    Timer { id: ttyPoll; interval: 3000; repeat: true; running: true; onTriggered: { if (!ttyScanner.running) ttyScanner.start() } }

    Column {
        anchors.fill:parent; anchors.margins:root._pad; spacing:root._spacing

        RowLayout { width:parent.width; spacing:root._spacing
            MaterialIcon{icon:"monitoring";size:root._iconSz || 16;color:root.accentColor;Layout.alignment:Qt.AlignVCenter}
            Text{text:"System Dashboard";font.family:Theme.fontFamily;font.pixelSize:root._fontSize | 0;color:Theme.textPrimary;font.bold:true;Layout.alignment:Qt.AlignVCenter}
            Item{Layout.fillWidth:true}
            Rectangle{width:10;height:10;radius:5;color:root.journalReady?Theme.accentPrimary:"#ef4444";Layout.alignment:Qt.AlignVCenter}
            Text{text:"Journal";font.family:Theme.fontFamily;font.pixelSize:root._fontSizeSmall | 0;color:root.journalReady?Theme.textSecondary:"#ef4444";Layout.alignment:Qt.AlignVCenter} }

        Rectangle{width:parent.width;height:1;color:root.sepColor}

        Row { width:parent.width; spacing:10
            Rectangle{id:c1;width:(parent.width-parent.spacing*2)/3;height:root._cardH;radius:6;color:root.cardBg
                Column{anchors.centerIn:parent;spacing:2
                    Text{text:root.totalLogs.toString();font.family:Theme.fontFamily;font.pixelSize:root._fontSizeMedium | 0;color:Theme.textPrimary;font.bold:true;anchors.horizontalCenter:parent.horizontalCenter}
                    Text{text:"Log Lines";font.family:Theme.fontFamily;font.pixelSize:root._fontSizeSmall | 0;color:Theme.textSecondary;anchors.horizontalCenter:parent.horizontalCenter}}}
            Rectangle{id:c2;width:(parent.width-parent.spacing*2)/3;height:root._cardH;radius:6;color:root.cardBg
                Column{anchors.centerIn:parent;spacing:2
                    Text{text:root.errorCount.toString();font.family:Theme.fontFamily;font.pixelSize:root._fontSizeMedium | 0;color:root.errorCount>0?Theme.error:Theme.textPrimary;font.bold:true;anchors.horizontalCenter:parent.horizontalCenter}
                    Text{text:"Errors";font.family:Theme.fontFamily;font.pixelSize:root._fontSizeSmall | 0;color:Theme.textSecondary;anchors.horizontalCenter:parent.horizontalCenter}}}
            Rectangle{id:c3;width:(parent.width-parent.spacing*2)/3;height:root._cardH;radius:6;color:root.cardBg
                Column{anchors.centerIn:parent;spacing:2
                    Text{text:root.serviceCount.toString();font.family:Theme.fontFamily;font.pixelSize:root._fontSizeMedium | 0;color:Theme.textPrimary;font.bold:true;anchors.horizontalCenter:parent.horizontalCenter}
                    Text{text:"Services";font.family:Theme.fontFamily;font.pixelSize:root._fontSizeSmall | 0;color:Theme.textSecondary;anchors.horizontalCenter:parent.horizontalCenter}}} }

        Rectangle{width:parent.width;height:1;color:root.sepColor}

        Text{text:"Recent Logs";font.family:Theme.fontFamily;font.pixelSize:root._fontSize | 0;color:Theme.textPrimary;font.bold:true}
        Rectangle { width:parent.width; height:Math.max(200, root.height-240); radius:6; color:root.cardBg; clip:true
            ListView {
                anchors.fill: parent
                model:root.logEntries
                clip: true
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; }
                header: RowLayout { width:parent?parent.width:800
                    Text{text:"Time";font.family:Theme.fontFamily;font.pixelSize:root._fontSizeSmall | 0;color:Theme.textSecondary;font.bold:true;Layout.preferredWidth:70}
                    Text{text:"Service";font.family:Theme.fontFamily;font.pixelSize:root._fontSizeSmall | 0;color:Theme.textSecondary;font.bold:true;Layout.preferredWidth:140}
                    Text{text:"Message";font.family:Theme.fontFamily;font.pixelSize:root._fontSizeSmall | 0;color:Theme.textSecondary;font.bold:true;Layout.fillWidth:true;elide:Text.ElideRight} }
                delegate: Rectangle { width:parent?parent.width:800; height:24; radius:2; color:index%2===0?Color.withAlpha(root.accentDim,0.05):"transparent"
                    RowLayout { anchors.fill:parent; anchors.margins:2
                        Text{text:modelData.time;font.family:Theme.fontFamily;font.pixelSize:root._fontSizeSmall | 0;color:modelData.level==="error"?Theme.error:modelData.level==="warn"?Theme.warning:Theme.textSecondary;Layout.preferredWidth:70;elide:Text.ElideRight}
                        Text{text:modelData.service;font.family:Theme.fontFamily;font.pixelSize:root._fontSizeSmall | 0;color:Theme.textPrimary;Layout.preferredWidth:140;elide:Text.ElideRight}
                        Text{text:modelData.message;font.family:Theme.fontFamily;font.pixelSize:root._fontSizeSmall | 0;color:Theme.textSecondary;Layout.fillWidth:true;elide:Text.ElideRight} } } }
        }

        // ── TTY Output section ──
        Text{text:"TTY Output";font.family:Theme.fontFamily;font.pixelSize:root._fontSize | 0;color:Theme.textPrimary;font.bold:true;visible:root.ttyOutput.length>0}

        Repeater {
            model: root.ttyOutput
            delegate: Rectangle {
                width: parent.width
                height: Math.min(120, 22 * Math.max(1, (modelData.lines || []).length))
                radius: 6; color: root.cardBg; clip: true
                Column {
                    anchors.fill: parent; anchors.margins: 4
                    Text {
                        text: modelData.name
                        font.family: Theme.fontFamily
                        font.pixelSize: root._fontSizeSmall | 0
                        color: root.accentColor
                        font.bold: true
                    }
                    Text {
                        text: (modelData.lines || []).join("\n")
                        font.family: "monospace"
                        font.pixelSize: Math.round(root._fontSizeSmall * 0.85) | 0
                        color: Theme.textSecondary
                        width: parent.width
                        elide: Text.ElideNone
                        wrapMode: Text.WrapAnywhere
                    }
                }
            }
        }

        RowLayout { width:parent.width; spacing:8; Item{Layout.fillWidth:true} }
    }
}
