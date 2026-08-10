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
    // ── UI view of the notification ─────────────────────────────────
    // Notification.actions is read-only (quickshell C++), so the manager
    // exposes a filtered view here. kitty sends a "default" action with a
    // space label (click-to-focus); quickshell renders every action as a
    // button, which would draw an empty one. Dropping "default" matches
    // daemon conventions (mako/dunst treat it as click-on-body). Both the
    // toast and the center read actions from this wrapper, so filtering
    // here covers every surface.
    readonly property var actions: tracked.notif.actions.filter(a => a.identifier !== "default");

    // Display fields proxied so NotificationCard can take this wrapper as
    // its `notif` (the raw Notification stays available via `notif`).
    readonly property string summary: tracked.notif.summary;
    readonly property string body: tracked.notif.body;
    readonly property string appIcon: tracked.notif.appIcon;
    readonly property string image: tracked.notif.image;

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
