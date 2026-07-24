import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Settings
import "../../Helpers/Color.js" as Color

PanelOverlaySurface {
    id: root

    // ── Medieval glass-morphism style (matching calendar) ──
    backgroundColor: Color.withAlpha(Theme.surface, 0.85)
    borderColor: Color.withAlpha(Theme.accentPrimary, 0.15)
    borderWidth: 1
    cornerRadiusOverride: Math.round(Theme.cornerRadiusLarge / 3)

    anchors.top: parent.top
    anchors.right: parent.right
    anchors.topMargin: Math.round(8 * overlayScale)
    anchors.rightMargin: Math.round(8 * overlayScale)
    implicitWidth: Math.round(480 * overlayScale)
    implicitHeight: Math.round(520 * overlayScale)

    // Inner glow line (top border accent)
    Rectangle {
        anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
        height: 1; color: Color.withAlpha(Theme.accentPrimary, 0.25)
    }

    // ── Theme tokens ──
    readonly property color accentColor: Color.withAlpha(Theme.accentPrimary, 0.85)
    readonly property color accentDim: Color.withAlpha(Theme.accentPrimary, 0.35)
    readonly property color cardBg: Color.withAlpha(Theme.accentPrimary, 0.06)
    readonly property color cardBorder: Color.withAlpha(Theme.accentPrimary, 0.12)
    readonly property color separatorColor: Color.withAlpha(Theme.accentPrimary, 0.15)

    readonly property int _iconSz: Math.round(Theme.fontSizeSmall * overlayScale)
    readonly property int _fontSize: Math.round(Theme.fontSizeSmall * overlayScale)
    readonly property int _fontSizeSmall: Math.round(Theme.fontSizeSmall * 0.85 * overlayScale)
    readonly property int _fontSizeMedium: Math.round(Theme.fontSizeMedium * overlayScale)
    readonly property int _pad: Math.round(10 * overlayScale)
    readonly property int _spacing: Math.round(6 * overlayScale)
    readonly property string _grafanaBase: "http://127.0.0.1:3030"

    // ── Journal state ──
    property var logEntries: []
    property int totalLogs: 0
    property int errorCount: 0
    property int serviceCount: 0
    property bool journalReady: false

    property var _pendingEntries: []
    property var _pendingServices: ({})

    ProcessRunner {
        id: journalCtl
        cmd: ["/run/current-system/sw/bin/journalctl", "--no-pager", "-n", "80", "--output=json", "--since", "10 minutes ago"]
        autoStart: true; restartOnExit: false
        onLine: (s) => { root._parseJournalLine(s) }
        onExited: { root._finalizeJournalEntries() }
    }

    function _parseJournalLine(raw) {
        var s = String(raw).trim(); if (!s) return
        var obj; try { obj = JSON.parse(s) } catch (e) { return }
        var tsMicro = obj.__REALTIME_TIMESTAMP || "0"
        var date = new Date(parseInt(tsMicro.substring(0,13),10))
        var timeStr = ("0"+date.getHours()).slice(-2)+":"+("0"+date.getMinutes()).slice(-2)+":"+("0"+date.getSeconds()).slice(-2)
        var ident = obj.SYSLOG_IDENTIFIER || obj._SYSTEMD_UNIT || obj._COMM || "?"
        if (ident.length > 0) root._pendingServices[ident] = true
        var prio = parseInt(obj.PRIORITY,10)
        var level = "info"
        if (!isNaN(prio)) { if(prio<=3)level="error"; else if(prio===4)level="warn"; else if(prio>=7)level="debug" }
        else {
            var msgLower = String(obj.MESSAGE||"").toLowerCase()
            if(msgLower.indexOf("error")>=0||msgLower.indexOf("fail")>=0||msgLower.indexOf("fatal")>=0)level="error"
            else if(msgLower.indexOf("warn")>=0)level="warn"
            else if(msgLower.indexOf("debug")>=0)level="debug"
        }
        var msg = String(obj.MESSAGE||"")
        root._pendingEntries.push({time:timeStr,level:level,service:ident,message:msg.length>150?msg.substring(0,150)+"...":msg})
    }

    function _finalizeJournalEntries() {
        if (!root._pendingEntries || root._pendingEntries.length===0) return
        var errors=0; for(var i=0;i<root._pendingEntries.length;i++){if(root._pendingEntries[i].level==="error")errors++}
        root.logEntries=root._pendingEntries; root.totalLogs=root._pendingEntries.length
        root.errorCount=errors; root.serviceCount=Object.keys(root._pendingServices).length; root.journalReady=true
    }

    function refreshAll() { root._pendingEntries=[]; root._pendingServices=({}); root.journalReady=false; journalCtl.stop(); journalCtl.start() }

    Timer { interval:15000; repeat:true; running:true; triggeredOnStart:false; onTriggered:root.refreshAll() }

    // ── UI ──
    Column {
        anchors.fill: parent
        anchors.margins: root._pad
        spacing: root._spacing

        // Header
        RowLayout {
            width: parent.width; spacing: root._spacing
            MaterialIcon { icon:"monitoring"; size:root._iconSz; color:root.accentColor; Layout.alignment:Qt.AlignVCenter }
            Text { text:"System Dashboard"; font.family:Theme.fontFamily; font.pixelSize:root._fontSize; color:Theme.textPrimary; font.bold:true; Layout.alignment:Qt.AlignVCenter }
            Item { Layout.fillWidth:true }
            Rectangle { width:Math.round(8*overlayScale); height:width; radius:width/2; color:root.journalReady?Theme.accentPrimary:"#ef4444"; Layout.alignment:Qt.AlignVCenter }
            Text { text:"Journal"; font.family:Theme.fontFamily; font.pixelSize:root._fontSizeSmall; color:root.journalReady?Theme.textSecondary:"#ef4444"; Layout.alignment:Qt.AlignVCenter }
        }

        Rectangle { width:parent.width; height:1; color:root.separatorColor }

        // Stat cards
        Row {
            width: parent.width; spacing: Math.round(8*overlayScale)
            Rectangle { id:totalCard; width:(parent.width-parent.spacing*2)/3; height:Math.round(52*overlayScale); radius:Math.round(6*overlayScale); color:root.cardBg; border.color:root.cardBorder; border.width:1
                Column { anchors.centerIn:parent; spacing:Math.round(2*overlayScale)
                    Text { text:root.totalLogs.toString(); font.family:Theme.fontFamily; font.pixelSize:root._fontSizeMedium; color:Theme.textPrimary; font.bold:true; anchors.horizontalCenter:parent.horizontalCenter }
                    Text { text:"Log Lines"; font.family:Theme.fontFamily; font.pixelSize:root._fontSizeSmall; color:Theme.textSecondary; anchors.horizontalCenter:parent.horizontalCenter } } }
            Rectangle { id:errorsCard; width:(parent.width-parent.spacing*2)/3; height:Math.round(52*overlayScale); radius:Math.round(6*overlayScale); color:root.cardBg; border.color:root.cardBorder; border.width:1
                Column { anchors.centerIn:parent; spacing:Math.round(2*overlayScale)
                    Text { text:root.errorCount.toString(); font.family:Theme.fontFamily; font.pixelSize:root._fontSizeMedium; color:root.errorCount>0?Theme.error:Theme.textPrimary; font.bold:true; anchors.horizontalCenter:parent.horizontalCenter }
                    Text { text:"Errors"; font.family:Theme.fontFamily; font.pixelSize:root._fontSizeSmall; color:Theme.textSecondary; anchors.horizontalCenter:parent.horizontalCenter } } }
            Rectangle { id:servicesCard; width:(parent.width-parent.spacing*2)/3; height:Math.round(52*overlayScale); radius:Math.round(6*overlayScale); color:root.cardBg; border.color:root.cardBorder; border.width:1
                Column { anchors.centerIn:parent; spacing:Math.round(2*overlayScale)
                    Text { text:root.serviceCount.toString(); font.family:Theme.fontFamily; font.pixelSize:root._fontSizeMedium; color:Theme.textPrimary; font.bold:true; anchors.horizontalCenter:parent.horizontalCenter }
                    Text { text:"Services"; font.family:Theme.fontFamily; font.pixelSize:root._fontSizeSmall; color:Theme.textSecondary; anchors.horizontalCenter:parent.horizontalCenter } } }
        }

        Rectangle { width:parent.width; height:1; color:root.separatorColor }

        // Log viewer header
        Text { text:"Recent Logs"; font.family:Theme.fontFamily; font.pixelSize:root._fontSize; color:Theme.textPrimary; font.bold:true }

        // Log viewer
        Rectangle {
            width: parent.width; height: Math.round(200*overlayScale); radius: Math.round(6*overlayScale)
            color: root.cardBg; border.color: root.cardBorder; border.width: 1; clip: true

            ListView {
                anchors.fill: parent; anchors.margins: Math.round(4*overlayScale)
                model: root.logEntries; spacing: Math.round(2*overlayScale)

                header: RowLayout {
                    width: parent ? parent.width : 400
                    Text { text:"Time"; font.family:Theme.fontFamily; font.pixelSize:root._fontSizeSmall; color:Theme.textSecondary; font.bold:true; Layout.preferredWidth:Math.round(60*overlayScale) }
                    Text { text:"Service"; font.family:Theme.fontFamily; font.pixelSize:root._fontSizeSmall; color:Theme.textSecondary; font.bold:true; Layout.preferredWidth:Math.round(100*overlayScale) }
                    Text { text:"Message"; font.family:Theme.fontFamily; font.pixelSize:root._fontSizeSmall; color:Theme.textSecondary; font.bold:true; Layout.fillWidth:true; elide:Text.ElideRight }
                }

                delegate: Rectangle {
                    width: parent ? parent.width : 400; height: Math.round(20*overlayScale)
                    radius: 2; color: index%2===0 ? Color.withAlpha(root.accentDim,0.05) : "transparent"

                    RowLayout {
                        anchors.fill: parent; anchors.margins: Math.round(2*overlayScale)
                        Text { text:modelData.time; font.family:Theme.fontFamily; font.pixelSize:root._fontSizeSmall; color:modelData.level==="error"?Theme.error:modelData.level==="warn"?Theme.warning:Theme.textSecondary
                            Layout.preferredWidth:Math.round(60*overlayScale); elide:Text.ElideRight }
                        Text { text:modelData.service; font.family:Theme.fontFamily; font.pixelSize:root._fontSizeSmall; color:Theme.textPrimary
                            Layout.preferredWidth:Math.round(100*overlayScale); elide:Text.ElideRight }
                        Text { text:modelData.message; font.family:Theme.fontFamily; font.pixelSize:root._fontSizeSmall; color:Theme.textSecondary
                            Layout.fillWidth:true; elide:Text.ElideRight }
                    }
                }
            }
        }

        // Grafana quick links
        RowLayout {
            width: parent.width; spacing: Math.round(8*overlayScale)
            Item { Layout.fillWidth: true }
            Rectangle {
                radius: Math.round(4*overlayScale); color: root.cardBg; border.color: root.cardBorder; border.width: 1
                implicitWidth: grafanaLabel.implicitWidth + Math.round(16*overlayScale); implicitHeight: grafanaLabel.implicitHeight + Math.round(8*overlayScale)
                Text { id:grafanaLabel; anchors.centerIn:parent; text:"Grafana ↗"; font.family:Theme.fontFamily; font.pixelSize:root._fontSizeSmall; color:root.accentColor }
                MouseArea { anchors.fill:parent; onClicked:{ Qt.openUrlExternally(root._grafanaBase) } }
            }
        }
    }
}
