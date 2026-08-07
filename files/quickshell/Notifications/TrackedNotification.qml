pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.Notifications

Scope {
    id: tracked

    required property Notification notif;
    property Component renderComponent;
    property var visualizer: null;
    property bool inTray: false;
    property bool destroyOnInvisible: false;
    property real timePercentage: 1;
    property int pauseCounter: 0;
    property int expireTimeout: tracked.notif.expireTimeout;

    signal discarded();
    signal discard();

    function handleDiscard() {
        tracked.discarded();
    }

    function handleDismiss() {
        tracked.discard();
    }

    function untrack() {
        tracked.destroyOnInvisible = true;
        if (!tracked.visualizer) tracked.destroy();
    }
}
