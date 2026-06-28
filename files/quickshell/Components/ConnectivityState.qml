pragma Singleton
import QtQuick
import Quickshell.Services.SystemTray
import qs.Services as Services
import "../Helpers/ConnectivityUi.js" as ConnUi

QtObject {
    id: root

    // Direct bindings to Services.Connectivity
    readonly property bool hasLink: !!(Services.Connectivity && Services.Connectivity.hasLink)
    readonly property bool hasInternet: !!(Services.Connectivity && Services.Connectivity.hasInternet)
    readonly property real rxKiBps: (Services.Connectivity && Services.Connectivity.rxKiBps) || 0
    readonly property real txKiBps: (Services.Connectivity && Services.Connectivity.txKiBps) || 0
    readonly property var interfaces: (Services.Connectivity && Services.Connectivity.interfaces) || []

    // Derived data
    readonly property string throughputText: ConnUi.formatThroughput(rxKiBps, txKiBps) || "-/-"
    property bool vpnConnected: false
    property string vpnInterface: ""

    // Hiddify SNI tray item (null when Hiddify is not running)
    property var hiddifyTrayItem: null

    function updateVpnState(list) {
        const arr = Array.isArray(list) ? list : []
        let found = false
        let match = ""
        for (let it of arr) {
            const ifname = (it && it.ifname) ? String(it.ifname) : ""
            if (!ifname.length) continue
            const nameLower = ifname.toLowerCase()
            const looksVpn = nameLower.includes("awg") || nameLower.includes("amnez")
                          || nameLower.startsWith("tun") || nameLower.startsWith("outline-tun")
            if (!looksVpn) continue
            const addrs = Array.isArray(it?.addr_info) ? it.addr_info : []
            if (addrs.length > 0) {
                found = true
                match = ifname
                break
            }
        }
        vpnConnected = found
        vpnInterface = match
    }

    function _isHiddifyItem(item) {
        if (!item) return false
        const id = item.id ? String(item.id).toLowerCase() : ""
        const title = item.title ? String(item.title).toLowerCase() : ""
        return id.includes("hiddify") || title.includes("hiddify")
    }

    function updateHiddifyTrayItem() {
        const items = SystemTray.items
        const arr = Array.isArray(items) ? items : []
        for (let it of arr) {
            if (_isHiddifyItem(it)) {
                hiddifyTrayItem = it
                return
            }
        }
        hiddifyTrayItem = null
    }

    property Connections _interfaceWatcher: Connections {
        target: Services.Connectivity
        function onInterfacesChanged() {
            root.updateVpnState(Services.Connectivity.interfaces)
        }
    }

    property Connections _trayWatcher: Connections {
        target: SystemTray.items
        function onValuesChanged() { root.updateHiddifyTrayItem() }
    }

    Component.onCompleted: {
        updateVpnState(interfaces)
        updateHiddifyTrayItem()
    }
}
