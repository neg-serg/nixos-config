import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Settings
import "../../Helpers/SystemMonitorUi.js" as SysUi

PanelOverlaySurface {
    id: root
    backgroundColor: Theme.background

    anchors.top: parent.top
    anchors.right: parent.right
    anchors.topMargin: Math.round(8 * overlayScale)
    anchors.rightMargin: Math.round(8 * overlayScale)
    implicitWidth: Math.round(480 * overlayScale)
    implicitHeight: Math.round(520 * overlayScale)

    readonly property int _iconSz: Math.round(Theme.fontSizeSmall * overlayScale)
    readonly property int _fontSize: Math.round(Theme.fontSizeSmall * overlayScale)
    readonly property int _fontSizeSmall: Math.round(Theme.fontSizeSmall * 0.85 * overlayScale)
    readonly property int _fontSizeMedium: Math.round(Theme.fontSizeMedium * overlayScale)
    readonly property int _fontSizeTiny: Math.round(9 * overlayScale)
    readonly property int _pad: Math.round(10 * overlayScale)
    readonly property int _spacing: Math.round(6 * overlayScale)
    readonly property string _grafanaBase: "http://127.0.0.1:3030"

    property var logEntries: []
    property int totalLogs: 0
    property int errorCount: 0
    property int serviceCount: 0
    property bool journalReady: false

    // Fetch logs from journald directly via journalctl
    ProcessRunner {
        id: journalCtl
        cmd: ["/run/current-system/sw/bin/journalctl", "--no-pager", "-n", "80", "--output=json", "--since", "10 minutes ago"]
        autoStart: true
        restartOnExit: false
        onLine: (s) => { root._parseJournalLine(s) }
        onExited: {
            root._finalizeJournalEntries()
        }
    }

    property var _pendingEntries: []
    property var _pendingServices: ({})

    function _parseJournalLine(raw) {
        var s = String(raw).trim()
        if (!s) return
        var obj
        try { obj = JSON.parse(s) } catch (e) { return }

        // Extract fields
        var tsMicro = obj.__REALTIME_TIMESTAMP || "0"
        var date = new Date(parseInt(tsMicro.substring(0, 13), 10))
        var timeStr = ("0" + date.getHours()).slice(-2) + ":" +
                      ("0" + date.getMinutes()).slice(-2) + ":" +
                      ("0" + date.getSeconds()).slice(-2)

        var ident = obj.SYSLOG_IDENTIFIER || obj._SYSTEMD_UNIT || obj._COMM || "?"
        if (ident && ident.length > 0) root._pendingServices[ident] = true

        // Map priority 0..7 to level string
        var prio = parseInt(obj.PRIORITY, 10)
        var level = "info"
        if (!isNaN(prio)) {
            if (prio <= 3) level = "error"
            else if (prio === 4) level = "warn"
            else if (prio >= 7) level = "debug"
        } else {
            // Fallback: heuristic level detection from message content
            var msgLower = String(obj.MESSAGE || "").toLowerCase()
            if (msgLower.indexOf("error") >= 0 || msgLower.indexOf("fail") >= 0 ||
                msgLower.indexOf("fatal") >= 0) level = "error"
            else if (msgLower.indexOf("warn") >= 0) level = "warn"
            else if (msgLower.indexOf("debug") >= 0) level = "debug"
        }

        var msg = String(obj.MESSAGE || "")
        root._pendingEntries.push({
            time: timeStr,
            level: level,
            service: ident,
            message: msg.length > 150 ? msg.substring(0, 150) + "..." : msg
        })
    }

    function _finalizeJournalEntries() {
        // Ignore empty results (e.g. from a killed/stopped process during refresh)
        if (!root._pendingEntries || root._pendingEntries.length === 0) return

        var errors = 0
        for (var i = 0; i < root._pendingEntries.length; i++) {
            if (root._pendingEntries[i].level === "error") errors++
        }
        root.logEntries = root._pendingEntries
        root.totalLogs = root._pendingEntries.length
        root.errorCount = errors
        root.serviceCount = Object.keys(root._pendingServices).length
        root.journalReady = true
    }

    function openGrafana() {
        Qt.openUrlExternally(_grafanaBase)
    }

    function openDashboard(uid) {
        Qt.openUrlExternally(_grafanaBase + "/d/" + uid)
    }

    function refreshAll() {
        root._pendingEntries = []
        root._pendingServices = ({})
        root.journalReady = false
        // Restart journalctl process
        journalCtl.stop()
        journalCtl.start()
    }

    // journalCtl auto-starts via autoStart:true — no need to kick it manually
    Timer {
        interval: 15000
        repeat: true
        running: true
        triggeredOnStart: false
        onTriggered: root.refreshAll()
    }

    Column {
        id: popupContent
        anchors.fill: parent
        anchors.margins: root._pad
        spacing: root._spacing

        Column {
            width: parent.width
            spacing: root._spacing

            RowLayout {
                width: parent.width
                spacing: root._spacing

                MaterialIcon {
                    icon: "monitoring"
                    size: root._iconSz
                    color: Theme.accentPrimary
                    Layout.alignment: Qt.AlignVCenter
                }
                Text {
                    text: "System Dashboard"
                    font.family: Theme.fontFamily
                    font.pixelSize: root._fontSize
                    color: Theme.textPrimary
                    font.bold: true
                    Layout.alignment: Qt.AlignVCenter
                }
                Item { Layout.fillWidth: true }

                Rectangle {
                    id: statusDot
                    width: Math.round(8 * overlayScale)
                    height: width
                    radius: width / 2
                    color: root.journalReady ? "#4ade80" : "#ef4444"
                    Layout.alignment: Qt.AlignVCenter
                }
                Text {
                    text: "Journal"
                    font.family: Theme.fontFamily
                    font.pixelSize: root._fontSizeSmall
                    color: root.journalReady ? Theme.textSecondary : "#ef4444"
                    Layout.alignment: Qt.AlignVCenter
                }
            }

            Rectangle {
                width: parent.width
                height: Math.round(1 * overlayScale)
                color: Theme.borderSubtle
            }

            Row {
                width: parent.width
                spacing: Math.round(8 * overlayScale)

                Rectangle {
                    id: totalCard
                    width: (parent.width - parent.spacing * 2) / 3
                    height: Math.round(52 * overlayScale)
                    radius: Math.round(6 * overlayScale)
                    color: Theme.overlayWeak
                    border.color: Theme.borderSubtle
                    border.width: 1

                    Column {
                        anchors.centerIn: parent
                        spacing: Math.round(2 * overlayScale)
                        Text {
                            text: root.totalLogs.toString()
                            font.family: Theme.fontFamily
                            font.pixelSize: root._fontSizeMedium
                            color: Theme.textPrimary
                            font.bold: true
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                        Text {
                            text: "Log Lines"
                            font.family: Theme.fontFamily
                            font.pixelSize: root._fontSizeSmall
                            color: Theme.textSecondary
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                }

                Rectangle {
                    id: errorsCard
                    width: (parent.width - parent.spacing * 2) / 3
                    height: Math.round(52 * overlayScale)
                    radius: Math.round(6 * overlayScale)
                    color: Theme.overlayWeak
                    border.color: Theme.borderSubtle
                    border.width: 1

                    Column {
                        anchors.centerIn: parent
                        spacing: Math.round(2 * overlayScale)
                        Text {
                            text: root.errorCount.toString()
                            font.family: Theme.fontFamily
                            font.pixelSize: root._fontSizeMedium
                            color: root.errorCount > 0 ? "#ef4444" : Theme.textPrimary
                            font.bold: true
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                        Text {
                            text: "Errors"
                            font.family: Theme.fontFamily
                            font.pixelSize: root._fontSizeSmall
                            color: Theme.textSecondary
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                }

                Rectangle {
                    id: servicesCard
                    width: (parent.width - parent.spacing * 2) / 3
                    height: Math.round(52 * overlayScale)
                    radius: Math.round(6 * overlayScale)
                    color: Theme.overlayWeak
                    border.color: Theme.borderSubtle
                    border.width: 1

                    Column {
                        anchors.centerIn: parent
                        spacing: Math.round(2 * overlayScale)
                        Text {
                            text: root.serviceCount.toString()
                            font.family: Theme.fontFamily
                            font.pixelSize: root._fontSizeMedium
                            color: Theme.textPrimary
                            font.bold: true
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                        Text {
                            text: "Services"
                            font.family: Theme.fontFamily
                            font.pixelSize: root._fontSizeSmall
                            color: Theme.textSecondary
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: Math.round(1 * overlayScale)
                color: Theme.borderSubtle
            }

            Text {
                text: "Recent Logs"
                font.family: Theme.fontFamily
                font.pixelSize: root._fontSize
                color: Theme.textPrimary
                font.bold: true
            }

            Rectangle {
                id: logArea
                width: parent.width
                height: Math.round(200 * overlayScale)
                radius: Math.round(6 * overlayScale)
                color: Theme.overlayWeak
                clip: true

                ListView {
                    id: logList
                    anchors.fill: parent
                    anchors.margins: Math.round(4 * overlayScale)
                    model: root.logEntries
                    spacing: Math.round(2 * overlayScale)

                    delegate: Row {
                        width: logList.width - Math.round(8 * overlayScale)
                        spacing: Math.round(6 * overlayScale)
                        height: Math.round(18 * overlayScale)

                        Text {
                            text: modelData.time
                            font.family: Theme.fontFamily
                            font.pixelSize: root._fontSizeSmall
                            color: Theme.textSecondary
                            font.letterSpacing: -0.5
                            width: Math.round(52 * overlayScale)
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Rectangle {
                            width: Math.round(4 * overlayScale)
                            height: Math.round(12 * overlayScale)
                            radius: Math.round(2 * overlayScale)
                            color: modelData.level === "error" ? "#ef4444"
                                 : modelData.level === "warn" ? "#eab308"
                                 : modelData.level === "debug" ? "#6b7280"
                                 : "#22c55e"
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: modelData.service
                            font.family: Theme.fontFamily
                            font.pixelSize: root._fontSizeSmall
                            color: Theme.accentPrimary
                            width: Math.round(80 * overlayScale)
                            elide: Text.ElideRight
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: modelData.message
                            font.family: Theme.fontFamily
                            font.pixelSize: root._fontSizeSmall
                            color: modelData.level === "error" ? "#fca5a5"
                                 : modelData.level === "warn" ? "#fde047"
                                 : Theme.textPrimary
                            elide: Text.ElideRight
                            width: parent.width - Math.round(150 * overlayScale)
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: Math.round(1 * overlayScale)
                color: Theme.borderSubtle
            }

            Row {
                width: parent.width
                spacing: Math.round(8 * overlayScale)

                Rectangle {
                    id: journalBtn
                    width: (parent.width - Math.round(16 * overlayScale)) / 3
                    height: Math.round(32 * overlayScale)
                    radius: Math.round(6 * overlayScale)
                    color: Theme.overlayWeak
                    border.color: Theme.borderSubtle
                    border.width: 1

                    property bool _hovered: false

                    Row {
                        anchors.centerIn: parent
                        spacing: Math.round(4 * overlayScale)
                        MaterialIcon {
                            icon: "article"
                            size: Math.round(14 * overlayScale)
                            color: Theme.textPrimary
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: "Journal"
                            font.family: Theme.fontFamily
                            font.pixelSize: root._fontSizeSmall
                            color: Theme.textPrimary
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    TapHandler {
                        gesturePolicy: TapHandler.ReleaseWithinBounds
                        onTapped: root.openDashboard("system-journal")
                    }
                    HoverHandler {
                        onHoveredChanged: journalBtn._hovered = hovered
                    }
                }

                Rectangle {
                    id: metricsBtn
                    width: (parent.width - Math.round(16 * overlayScale)) / 3
                    height: Math.round(32 * overlayScale)
                    radius: Math.round(6 * overlayScale)
                    color: Theme.overlayWeak
                    border.color: Theme.borderSubtle
                    border.width: 1

                    property bool _hovered: false

                    Row {
                        anchors.centerIn: parent
                        spacing: Math.round(4 * overlayScale)
                        MaterialIcon {
                            icon: "monitoring"
                            size: Math.round(14 * overlayScale)
                            color: Theme.textPrimary
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: "Metrics"
                            font.family: Theme.fontFamily
                            font.pixelSize: root._fontSizeSmall
                            color: Theme.textPrimary
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    TapHandler {
                        gesturePolicy: TapHandler.ReleaseWithinBounds
                        onTapped: root.openDashboard("system-metrics")
                    }
                    HoverHandler {
                        onHoveredChanged: metricsBtn._hovered = hovered
                    }
                }

                Rectangle {
                    id: refreshBtn
                    width: (parent.width - Math.round(16 * overlayScale)) / 3
                    height: Math.round(32 * overlayScale)
                    radius: Math.round(6 * overlayScale)
                    color: Theme.overlayWeak
                    border.color: Theme.borderSubtle
                    border.width: 1

                    property bool _hovered: false

                    Row {
                        anchors.centerIn: parent
                        spacing: Math.round(4 * overlayScale)
                        MaterialIcon {
                            icon: "refresh"
                            size: Math.round(14 * overlayScale)
                            color: Theme.textPrimary
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: "Refresh"
                            font.family: Theme.fontFamily
                            font.pixelSize: root._fontSizeSmall
                            color: Theme.textPrimary
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    TapHandler {
                        gesturePolicy: TapHandler.ReleaseWithinBounds
                        onTapped: root.refreshAll()
                    }
                    HoverHandler {
                        onHoveredChanged: refreshBtn._hovered = hovered
                    }
                }
            }

            Text {
                text: "journal-ready=" + root.journalReady + " entries=" + root.totalLogs
                font.family: Theme.fontFamily
                font.pixelSize: root._fontSizeTiny
                color: Theme.textSecondary
                visible: Settings.settings.debugLogs === true
            }
        }
    }
}
