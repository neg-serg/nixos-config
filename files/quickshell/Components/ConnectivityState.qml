pragma Singleton
import QtQuick
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
    readonly property string throughputText: ConnUi.formatThroughput(rxKiBps, txKiBps) || "0"
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

    Component.onCompleted: {
        console.log("[ConnectivityState] singleton loaded. hasLink:", root.hasLink, "hasInternet:", root.hasInternet);
        updateVpnState(interfaces);
    }
}
