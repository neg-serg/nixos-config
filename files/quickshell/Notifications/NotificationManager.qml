pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Notifications

Singleton {
    id: root

    property list<TrackedNotification> notifications;
    property Component notifComponent: DaemonNotification {}

    property bool showTrayNotifs: false;
    property bool dnd: false;
    property bool hasNotifs: root.notifications.length !== 0
    // Dismissed notifications, kept for the center's history (Android-style).
    property list<TrackedNotification> history;
    property int maxHistory: 50

    property int maxToastCount: 2


    signal notif(notif: TrackedNotification);
    signal showAll(notifications: list<TrackedNotification>);
    signal dismissAll(notifications: list<TrackedNotification>);
    signal discardAll(notifications: list<TrackedNotification>);

    NotificationServer {
        id: notificationServer
        imageSupported: true
        actionsSupported: true
        actionIconsSupported: true

        onNotification: notification => {
            notification.tracked = true;

            const notif = root.notifComponent.createObject(null, { notif: notification });
            if (!notif) return;
            root.notifications = [...root.notifications, notif];

            root.notif(notif);
        }
    }

    Instantiator {
        id: notificationInstantiator
        model: root.notifications

        Connections {
            id: notificationConnection
            required property TrackedNotification modelData;
            target: notificationConnection.modelData;

            function onDiscarded() {
                const n = notificationConnection.target;
                root.notifications = root.notifications.filter(x => x !== n);
                // Keep it for the history section instead of dropping it.
                const capped = root.history.length >= root.maxHistory ? root.history.slice(1) : root.history;
                root.history = [...capped, n];
                n.untrack();
            }

            function onDiscard() {
                if (!notificationConnection.modelData.visualizer) {
                    notificationConnection.modelData.discarded();
                }
            }
        }
    }

    onShowTrayNotifsChanged: {
        if (root.showTrayNotifs) {
            for (let i = 0; i < root.notifications.length; i++) {
                root.notifications[i].inTray = true;
            }
            root.showAll(root.notifications);
        } else {
            root.dismissAll(root.notifications);
        }
    }

    function openHistory() {
        root.showTrayNotifs = true;
    }

    function closeHistory() {
        root.showTrayNotifs = false;
    }

    function dismissAllActive() {
        root.dismissAll(root.notifications);
    }

    function sendDiscardAll() {
        root.discardAll(root.notifications);
        root.history = [];
    }
}
