import QtQuick
import qs.Components
import qs.Settings
import qs.Services as Services
import "../../Helpers/SystemMonitorUi.js" as SysUi
import "../../Helpers/TooltipText.js" as TooltipText

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
    // Tooltip on capsule hover: live CPU/GPU/RAM/temperature summary.
    readonly property string _tooltipText: (function() {
        var m = Services.SystemMonitor;
        var hints = [];
        if (m) {
            hints.push("CPU: " + Math.round(m.cpuPercent) + "%");
            if (m.gpuAvailable) hints.push("GPU: " + Math.round(m.gpuPercent) + "%");
            if (m.ramTotalGiB > 0)
                hints.push("RAM: " + Math.round(m.ramPercent) + "% (" + m.ramUsedGiB.toFixed(1) + " / " + m.ramTotalGiB.toFixed(0) + " GiB)");
            if (m.cpuTempCelsius > 0) hints.push("Температура: " + Math.round(m.cpuTempCelsius) + "°C");
        }
        hints.push("Клик — панель мониторинга");
        return TooltipText.compose("Мониторинг", "", hints);
    })()
    PanelTooltip{text:root._tooltipText;targetItem:root;visibleWhen:capsHov.containsMouse}
    MouseArea{id:capsHov;z:-1;anchors.fill:parent;hoverEnabled:true;acceptedButtons:Qt.NoButton}
    overlayNamespace: "qs-monitor"

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

        // Metric rows; the getters keep every value a live binding.
        Repeater {
            model: [
                { icon: "memory_alt",      shown: function() { return root._visCpu; },  idle: function() { return root._idleCpu; },  value: function() { return Services.SystemMonitor.cpuPercent; },      warn: function() { return root._warnThr; }, crit: function() { return root._critThr; } },
                { icon: "memory",          shown: function() { return root._visRam; },  idle: function() { return root._idleRam; },  value: function() { return Services.SystemMonitor.ramPercent; },      warn: function() { return root._warnThr; }, crit: function() { return root._critThr; } },
                { icon: "developer_board", shown: function() { return root._visGpu; },  idle: function() { return root._idleGpu; },  value: function() { return Services.SystemMonitor.gpuPercent; },      warn: function() { return root._warnThr; }, crit: function() { return root._critThr; } },
                { icon: "thermostat",      shown: function() { return root._visTemp; }, idle: function() { return root._idleTemp; }, value: function() { return Services.SystemMonitor.cpuTempPercent; },  warn: function() { return 0.43; },          crit: function() { return 0.71; } },
                { icon: "storage",         shown: function() { return root._visIo; },   idle: function() { return root._idleIo; },   value: function() { return Services.SystemMonitor.ioPercent; },       warn: function() { return root._warnThr; }, crit: function() { return root._critThr; } },
                { icon: "swap_horiz",      shown: function() { return root._visSwap; }, idle: function() { return root._idleSwap; }, value: function() { return Services.SystemMonitor.swapPercent; },     warn: function() { return root._warnThr; }, crit: function() { return root._critThr; } }
            ]
            delegate: Row {
                visible: modelData.shown()
                spacing: Math.round(2 * capsuleScale)
                anchors.verticalCenter: parent.verticalCenter
                MaterialIcon {
                    icon: modelData.icon
                    size: root._iconSz
                    color: modelData.idle() ? Theme.textDisabled : SysUi.thresholdColor(modelData.value(),
                        Theme.textSecondary, Theme.warning, Theme.error, modelData.warn(), modelData.crit())
                    Behavior on color { ColorFastInOutBehavior {} }
                    anchors.verticalCenter: parent.verticalCenter
                }
                MonitorBar {
                    value: modelData.value()
                    barHeight: root.barH
                    warnThreshold: modelData.warn()
                    critThreshold: modelData.crit()
                    screen: root.screen
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    overlayChildren: [
        SystemMonitorPopup {
            id: monitorPopup
            screen: root.screen
            scaleHint: capsuleScale
        }
    ]

    // Copy journal problems to clipboard each time the dashboard opens;
    // cancel a pending copy if it is dismissed before data is ready.
    onOpened: monitorPopup.copyProblemsToClipboard()
    onDismissed: monitorPopup.cancelPendingCopy()
}
