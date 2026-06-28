import QtQuick
import qs.Components
import qs.Settings
import qs.Services as Services
import "../../Helpers/SystemMonitorUi.js" as SysUi

/*!
 * SystemMonitorCapsule — grouped capsule showing 6 system metrics as
 * icon + vertical bar pairs. Click to open detail popup.
 */
OverlayToggleCapsule {
    id: root
    readonly property real capsuleScale: capsule.capsuleScale
    readonly property int iconBox: capsule.capsuleInner
    readonly property int barH: Math.round(Theme.panelHeight * 0.55 * capsuleScale)
    capsule.backgroundKey: "systemMonitor"
    capsule.centerContent: true
    capsule.cursorShape: Qt.PointingHandCursor
    capsule.implicitWidth: capsule.horizontalPadding * 2 + metricsRow.implicitWidth
    capsuleVisible: _anyVisible
    autoToggleOnTap: true
    overlayNamespace: "sysmon-popup"

    // ── Settings ──
    readonly property bool _hideIdle: Settings.settings.systemMonitorHideIdle !== false
    readonly property real _idleThreshold: {
        var v = Settings.settings.systemMonitorIdleThreshold;
        return (typeof v === "number" && v >= 0) ? v : 0.03;
    }
    readonly property real _iconScale: {
        var v = Settings.settings.systemMonitorIconScale;
        return (typeof v === "number" && v > 0) ? v : 0.85;
    }
    readonly property int _metricSpacing: {
        var v = Settings.settings.systemMonitorSpacing;
        return (typeof v === "number" && v >= 0) ? Math.round(v * capsuleScale) : Math.round(3 * capsuleScale);
    }
    readonly property real _warnThr: {
        var v = Settings.settings.systemMonitorWarnThreshold;
        return (typeof v === "number" && v > 0) ? v : 0.5;
    }
    readonly property real _critThr: {
        var v = Settings.settings.systemMonitorCritThreshold;
        return (typeof v === "number" && v > 0) ? v : 0.8;
    }
    readonly property int _iconSz: Math.round(iconBox * _iconScale)

    // ── Visibility (setting gate) and idle state (for dimming) ──
    readonly property bool _visCpu: Settings.settings.showCpuMonitor !== false
    readonly property bool _visRam: Settings.settings.showRamMonitor !== false
    readonly property bool _visIo: Settings.settings.showIoMonitor !== false
        && !_idleIo
    readonly property bool _visGpu: Services.SystemMonitor.gpuAvailable
        && Settings.settings.showGpuMonitor !== false
    readonly property bool _visTemp: Settings.settings.showTempMonitor !== false
    readonly property real _swapShowThreshold: {
        var v = Settings.settings.systemMonitorSwapShowThreshold;
        return (typeof v === "number" && v >= 0) ? v : 0.4;
    }
    readonly property bool _visSwap: Services.SystemMonitor.swapAvailable
        && Settings.settings.showSwapMonitor !== false
        && Services.SystemMonitor.swapPercent >= _swapShowThreshold
    readonly property bool _anyVisible: _visCpu || _visRam || _visIo || _visGpu || _visTemp || _visSwap

    readonly property bool _idleCpu: _hideIdle && Services.SystemMonitor.cpuPercent < _idleThreshold
    readonly property bool _idleRam: _hideIdle && Services.SystemMonitor.ramPercent < _idleThreshold
    readonly property bool _idleIo: _hideIdle && Services.SystemMonitor.ioPercent < _idleThreshold
    readonly property bool _idleGpu: _hideIdle && Services.SystemMonitor.gpuPercent < _idleThreshold
    readonly property bool _idleTemp: _hideIdle && Services.SystemMonitor.cpuTempPercent < _idleThreshold
    readonly property bool _idleSwap: _hideIdle && Services.SystemMonitor.swapPercent < _idleThreshold

    Row {
        id: metricsRow
        anchors.centerIn: parent
        spacing: root._metricSpacing

        // ── CPU ──
        Row {
            visible: root._visCpu
            spacing: Math.round(2 * capsuleScale)
            anchors.verticalCenter: parent.verticalCenter
            MaterialIcon {
                icon: "memory_alt"
                size: root._iconSz
                color: root._idleCpu ? Theme.textDisabled : SysUi.thresholdColor(Services.SystemMonitor.cpuPercent,
                    Theme.textSecondary, Theme.warning, Theme.error, root._warnThr, root._critThr)
                Behavior on color { ColorFastInOutBehavior {} }
                anchors.verticalCenter: parent.verticalCenter
            }
            MonitorBar {
                value: Services.SystemMonitor.cpuPercent
                barHeight: root.barH
                warnThreshold: root._warnThr
                critThreshold: root._critThr
                screen: root.screen
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // ── RAM ──
        Row {
            visible: root._visRam
            spacing: Math.round(2 * capsuleScale)
            anchors.verticalCenter: parent.verticalCenter
            MaterialIcon {
                icon: "memory"
                size: root._iconSz
                color: root._idleRam ? Theme.textDisabled : SysUi.thresholdColor(Services.SystemMonitor.ramPercent,
                    Theme.textSecondary, Theme.warning, Theme.error, root._warnThr, root._critThr)
                Behavior on color { ColorFastInOutBehavior {} }
                anchors.verticalCenter: parent.verticalCenter
            }
            MonitorBar {
                value: Services.SystemMonitor.ramPercent
                barHeight: root.barH
                warnThreshold: root._warnThr
                critThreshold: root._critThr
                screen: root.screen
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // ── GPU ──
        Row {
            visible: root._visGpu
            spacing: Math.round(2 * capsuleScale)
            anchors.verticalCenter: parent.verticalCenter
            MaterialIcon {
                icon: "developer_board"
                size: root._iconSz
                color: root._idleGpu ? Theme.textDisabled : SysUi.thresholdColor(Services.SystemMonitor.gpuPercent,
                    Theme.textSecondary, Theme.warning, Theme.error, root._warnThr, root._critThr)
                Behavior on color { ColorFastInOutBehavior {} }
                anchors.verticalCenter: parent.verticalCenter
            }
            MonitorBar {
                value: Services.SystemMonitor.gpuPercent
                barHeight: root.barH
                warnThreshold: root._warnThr
                critThreshold: root._critThr
                screen: root.screen
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // ── Temperature ──
        Row {
            visible: root._visTemp
            spacing: Math.round(2 * capsuleScale)
            anchors.verticalCenter: parent.verticalCenter
            MaterialIcon {
                icon: "thermostat"
                size: root._iconSz
                color: root._idleTemp ? Theme.textDisabled : SysUi.thresholdColor(Services.SystemMonitor.cpuTempPercent,
                    Theme.textSecondary, Theme.warning, Theme.error, 0.43, 0.71)
                Behavior on color { ColorFastInOutBehavior {} }
                anchors.verticalCenter: parent.verticalCenter
            }
            MonitorBar {
                value: Services.SystemMonitor.cpuTempPercent
                barHeight: root.barH
                warnThreshold: 0.43
                critThreshold: 0.71
                screen: root.screen
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // ── I/O ──
        Row {
            visible: root._visIo
            spacing: Math.round(2 * capsuleScale)
            anchors.verticalCenter: parent.verticalCenter
            MaterialIcon {
                icon: "storage"
                size: root._iconSz
                color: root._idleIo ? Theme.textDisabled : SysUi.thresholdColor(Services.SystemMonitor.ioPercent,
                    Theme.textSecondary, Theme.warning, Theme.error, root._warnThr, root._critThr)
                Behavior on color { ColorFastInOutBehavior {} }
                anchors.verticalCenter: parent.verticalCenter
            }
            MonitorBar {
                value: Services.SystemMonitor.ioPercent
                barHeight: root.barH
                warnThreshold: root._warnThr
                critThreshold: root._critThr
                screen: root.screen
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // ── Swap ──
        Row {
            visible: root._visSwap
            spacing: Math.round(2 * capsuleScale)
            anchors.verticalCenter: parent.verticalCenter
            MaterialIcon {
                icon: "swap_horiz"
                size: root._iconSz
                color: root._idleSwap ? Theme.textDisabled : SysUi.thresholdColor(Services.SystemMonitor.swapPercent,
                    Theme.textSecondary, Theme.warning, Theme.error, root._warnThr, root._critThr)
                Behavior on color { ColorFastInOutBehavior {} }
                anchors.verticalCenter: parent.verticalCenter
            }
            MonitorBar {
                value: Services.SystemMonitor.swapPercent
                barHeight: root.barH
                warnThreshold: root._warnThr
                critThreshold: root._critThr
                screen: root.screen
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    overlayChildren: [
        SystemMonitorPopup {
            screen: root.screen
            scaleHint: capsuleScale
        }
    ]
}
