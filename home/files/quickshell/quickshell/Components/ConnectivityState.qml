pragma Singleton
import QtQuick
import qs.Services as Services
import "../Helpers/ConnectivityUi.js" as ConnUi

QtObject {
    id: root

    // Direct bindings to Services.Connectivity
    readonly property bool hasLink: Services.Connectivity.hasLink
    readonly property bool hasInternet: Services.Connectivity.hasInternet
    readonly property real rxKiBps: Services.Connectivity.rxKiBps
    readonly property real txKiBps: Services.Connectivity.txKiBps
    readonly property var interfaces: Services.Connectivity.interfaces

    // Derived data
    readonly property string throughputText: ConnUi.formatThroughput(rxKiBps, txKiBps)
    property bool vpnConnected: false
    property string vpnInterface: ""

    function updateVpnState(list) {
        const arr = Array.isArray(list) ? list : []
        let found = false
        let match = ""
        for (let it of arr) {
            const ifname = (it && it.ifname) ? String(it.ifname) : ""
            if (!ifname.length) continue
            const nameLower = ifname.toLowerCase()
            const looksAmnezia = nameLower.includes("awg") || nameLower.includes("amnez")
            if (!looksAmnezia) continue
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

    property Connections _interfaceWatcher: Connections {
        target: Services.Connectivity
        function onInterfacesChanged() {
            root.updateVpnState(Services.Connectivity.interfaces)
        }
    }

    Component.onCompleted: updateVpnState(interfaces)
}
