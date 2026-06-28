import QtQuick
import qs.Components
import qs.Services as Services
import "../Helpers/Utils.js" as Utils

/*!
 * AudioEndpointCapsule augments AudioLevelCapsule with automatic bindings to
 * Services.Audio. It keeps the UI in sync with PipeWire state and wires wheel /
 * click gestures to the requested Service methods.
 */
AudioLevelCapsule {
    id: root

    // Service bindings (property names on Services.Audio)
    property string levelProperty: "volume"
    property string mutedProperty: "muted"
    property string changeMethod: ""
    property string toggleMethod: ""

    // Behaviour toggles
    property bool toggleOnClick: false

    function refreshFromService() {
        if (!Services.Audio || !levelProperty.length) return;
        const level = Services.Audio[levelProperty];
        if (level === undefined) return;
        const muted = mutedProperty.length ? !!Services.Audio[mutedProperty] : false;
        root.updateFrom(Utils.clamp(level, 0, 100), muted);
    }

    function _serviceStep() {
        if (!Services.Audio) return 1;
        const val = Services.Audio["step"];
        return (typeof val === "number" && !isNaN(val)) ? val : 1;
    }

    function invokeChange(direction) {
        if (!Services.Audio || !changeMethod.length) return;
        const fn = Services.Audio[changeMethod];
        if (typeof fn !== "function") return;
        fn.call(Services.Audio, direction > 0 ? _serviceStep() : -_serviceStep());
    }

    function invokeToggle() {
        if (!toggleOnClick || !Services.Audio || !toggleMethod.length) return;
        const fn = Services.Audio[toggleMethod];
        if (typeof fn === "function") {
            fn.call(Services.Audio);
        }
    }

    function _maybeHandle(prop) {
        if (prop === levelProperty || prop === mutedProperty) {
            refreshFromService();
        }
    }

    Connections {
        target: Services.Audio
        function onVolumeChanged() { root._maybeHandle("volume"); }
        function onMutedChanged() { root._maybeHandle("muted"); }
        function onMicVolumeChanged() { root._maybeHandle("micVolume"); }
        function onMicMutedChanged() { root._maybeHandle("micMuted"); }
        function onCurrentRouteChanged() { root.refreshFromService(); }
        function onIsProAudioSinkChanged() { root.refreshFromService(); }
    }

    Connections {
        target: root
        function onWheelStep(direction) { root.invokeChange(direction); }
        function onClicked() { root.invokeToggle(); }
    }

    Component.onCompleted: refreshFromService()
}
