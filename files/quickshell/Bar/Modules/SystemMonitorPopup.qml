import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Settings
import "../../Helpers/Color.js" as Color

PanelOverlaySurface {
    id: root

    backgroundColor: Color.withAlpha(Theme.surface, 0.85)
    borderColor: Color.withAlpha(Theme.accentPrimary, 0.15)
    borderWidth: 1
    cornerRadiusOverride: Math.round(Theme.cornerRadiusLarge / 3)

    anchors.centerIn: parent
    implicitWidth: Math.round(Math.min(960, parent.width * 0.85))
    implicitHeight: Math.round(Math.min(640, parent.height * 0.85))

    Rectangle { anchors.top:parent.top; anchors.left:parent.left; anchors.right:parent.right; height:1; color:Color.withAlpha(Theme.accentPrimary,0.25) }

    readonly property color accentColor: Color.withAlpha(Theme.accentPrimary, 0.85)
    readonly property color accentDim: Color.withAlpha(Theme.accentPrimary, 0.35)
    readonly property color cardBg: Color.withAlpha(Theme.accentPrimary, 0.06)
    readonly property color cardBorder: Color.withAlpha(Theme.accentPrimary, 0.12)
    readonly property color sepColor: Color.withAlpha(Theme.accentPrimary, 0.15)

    readonly property real _iconSz: Theme.fontSizeSmall * 1.2
    readonly property real _fontSize: Theme.fontSizeSmall * 1.2
    readonly property real _fontSizeSmall: Theme.fontSizeSmall * 0.95
    readonly property real _fontSizeMedium: Theme.fontSizeMedium * 1.2
    readonly property real _pad: 14
    readonly property real _spacing: 8
    readonly property string _grafanaBase: "http://127.0.0.1:3030"
    readonly property real _cardH: 56

    property var logEntries: []
    property int totalLogs: 0
    property int errorCount: 0
    property int serviceCount: 0
    property bool journalReady: false
    property var _pendingEntries: []
    property var _pendingServices: ({})

    ProcessRunner {
        id: journalCtl
        cmd: ["/run/current-system/sw/bin/journalctl","--no-pager","-n","120","--output=json","--since","15 minutes ago"]
        autoStart:true; restartOnExit:false
        onLine:(s)=>{root._parseJournalLine(s)}
        onExited:{root._finalizeJournalEntries()}
    }

    function _parseJournalLine(raw){var s=String(raw).trim();if(!s)return;var obj;try{obj=JSON.parse(s)}catch(e){return}
        var t=obj.__REALTIME_TIMESTAMP||"0";var d=new Date(parseInt(t.substring(0,13),10))
        var ts=("0"+d.getHours()).slice(-2)+":"+("0"+d.getMinutes()).slice(-2)+":"+("0"+d.getSeconds()).slice(-2)
        var id=obj.SYSLOG_IDENTIFIER||obj._SYSTEMD_UNIT||obj._COMM||"?";if(id.length>0)root._pendingServices[id]=true
        var p=parseInt(obj.PRIORITY,10);var lv="info"
        if(!isNaN(p)){if(p<=3)lv="error";else if(p===4)lv="warn";else if(p>=7)lv="debug"}
        else{var ml=String(obj.MESSAGE||"").toLowerCase();if(ml.indexOf("error")>=0||ml.indexOf("fail")>=0||ml.indexOf("fatal")>=0)lv="error";else if(ml.indexOf("warn")>=0)lv="warn";else if(ml.indexOf("debug")>=0)lv="debug"}
        var msg=String(obj.MESSAGE||"");root._pendingEntries.push({time:ts,level:lv,service:id,message:msg.length>200?msg.substring(0,200)+"...":msg})}

    function _finalizeJournalEntries(){if(!root._pendingEntries||root._pendingEntries.length===0)return
        var e=0;for(var i=0;i<root._pendingEntries.length;i++){if(root._pendingEntries[i].level==="error")e++}
        root.logEntries=root._pendingEntries;root.totalLogs=root._pendingEntries.length;root.errorCount=e;root.serviceCount=Object.keys(root._pendingServices).length;root.journalReady=true}

    function refreshAll(){root._pendingEntries=[];root._pendingServices=({});root.journalReady=false;journalCtl.stop();journalCtl.start()}
    Timer{interval:15000;repeat:true;running:true;triggeredOnStart:false;onTriggered:root.refreshAll()}

    Column {
        anchors.fill:parent; anchors.margins:root._pad; spacing:root._spacing

        RowLayout { width:parent.width; spacing:root._spacing
            MaterialIcon{icon:"monitoring";size:root._iconSz;color:root.accentColor;Layout.alignment:Qt.AlignVCenter}
            Text{text:"System Dashboard";font.family:Theme.fontFamily;font.pixelSize:root._fontSize;color:Theme.textPrimary;font.bold:true;Layout.alignment:Qt.AlignVCenter}
            Item{Layout.fillWidth:true}
            Rectangle{width:10;height:10;radius:5;color:root.journalReady?Theme.accentPrimary:"#ef4444";Layout.alignment:Qt.AlignVCenter}
            Text{text:"Journal";font.family:Theme.fontFamily;font.pixelSize:root._fontSizeSmall;color:root.journalReady?Theme.textSecondary:"#ef4444";Layout.alignment:Qt.AlignVCenter} }

        Rectangle{width:parent.width;height:1;color:root.sepColor}

        Row { width:parent.width; spacing:10
            Rectangle{w:(parent.width-parent.spacing*2)/3;h:root._cardH;radius:6;color:root.cardBg;border.color:root.cardBorder;border.width:1
                Column{anchors.centerIn:parent;spacing:2
                    Text{text:root.totalLogs.toString();font.family:Theme.fontFamily;font.pixelSize:root._fontSizeMedium;color:Theme.textPrimary;font.bold:true;anchors.horizontalCenter:parent.horizontalCenter}
                    Text{text:"Log Lines";font.family:Theme.fontFamily;font.pixelSize:root._fontSizeSmall;color:Theme.textSecondary;anchors.horizontalCenter:parent.horizontalCenter}}}
            Rectangle{w:(parent.width-parent.spacing*2)/3;h:root._cardH;radius:6;color:root.cardBg;border.color:root.cardBorder;border.width:1
                Column{anchors.centerIn:parent;spacing:2
                    Text{text:root.errorCount.toString();font.family:Theme.fontFamily;font.pixelSize:root._fontSizeMedium;color:root.errorCount>0?Theme.error:Theme.textPrimary;font.bold:true;anchors.horizontalCenter:parent.horizontalCenter}
                    Text{text:"Errors";font.family:Theme.fontFamily;font.pixelSize:root._fontSizeSmall;color:Theme.textSecondary;anchors.horizontalCenter:parent.horizontalCenter}}}
            Rectangle{w:(parent.width-parent.spacing*2)/3;h:root._cardH;radius:6;color:root.cardBg;border.color:root.cardBorder;border.width:1
                Column{anchors.centerIn:parent;spacing:2
                    Text{text:root.serviceCount.toString();font.family:Theme.fontFamily;font.pixelSize:root._fontSizeMedium;color:Theme.textPrimary;font.bold:true;anchors.horizontalCenter:parent.horizontalCenter}
                    Text{text:"Services";font.family:Theme.fontFamily;font.pixelSize:root._fontSizeSmall;color:Theme.textSecondary;anchors.horizontalCenter:parent.horizontalCenter}}} }

        Rectangle{width:parent.width;height:1;color:root.sepColor}

        Text{text:"Recent Logs";font.family:Theme.fontFamily;font.pixelSize:root._fontSize;color:Theme.textPrimary;font.bold:true}

        Rectangle { width:parent.width; height:parent.height-220; radius:6; color:root.cardBg; border.color:root.cardBorder; border.width:1; clip:true
            ListView {
                anchors.fill:parent; anchors.margins:4; spacing:2
                model:root.logEntries
                header: RowLayout { width:parent?parent.width:800
                    Text{text:"Time";font.family:Theme.fontFamily;font.pixelSize:root._fontSizeSmall;color:Theme.textSecondary;font.bold:true;Layout.preferredWidth:70}
                    Text{text:"Service";font.family:Theme.fontFamily;font.pixelSize:root._fontSizeSmall;color:Theme.textSecondary;font.bold:true;Layout.preferredWidth:140}
                    Text{text:"Message";font.family:Theme.fontFamily;font.pixelSize:root._fontSizeSmall;color:Theme.textSecondary;font.bold:true;Layout.fillWidth:true;elide:Text.ElideRight} }
                delegate: Rectangle { width:parent?parent.width:800; height:22; radius:2; color:index%2===0?Color.withAlpha(root.accentDim,0.05):"transparent"
                    RowLayout { anchors.fill:parent; anchors.margins:2
                        Text{text:modelData.time;font.family:Theme.fontFamily;font.pixelSize:root._fontSizeSmall;color:modelData.level==="error"?Theme.error:modelData.level==="warn"?Theme.warning:Theme.textSecondary;Layout.preferredWidth:70;elide:Text.ElideRight}
                        Text{text:modelData.service;font.family:Theme.fontFamily;font.pixelSize:root._fontSizeSmall;color:Theme.textPrimary;Layout.preferredWidth:140;elide:Text.ElideRight}
                        Text{text:modelData.message;font.family:Theme.fontFamily;font.pixelSize:root._fontSizeSmall;color:Theme.textSecondary;Layout.fillWidth:true;elide:Text.ElideRight} } } } }

        RowLayout { width:parent.width; spacing:8; Item{Layout.fillWidth:true}
            Rectangle { radius:4; color:root.cardBg; border.color:root.cardBorder; border.width:1; implicitWidth:tx.implicitWidth+16; implicitHeight:tx.implicitHeight+8
                Text{id:tx;anchors.centerIn:parent;text:"Grafana ↗";font.family:Theme.fontFamily;font.pixelSize:root._fontSizeSmall;color:root.accentColor}
                MouseArea{anchors.fill:parent;onClicked:{Qt.openUrlExternally(root._grafanaBase)}} } }
    }
}
