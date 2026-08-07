pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.Notifications

TrackedNotification {
    id: daemon


    renderComponent: NotificationCard {
        notif: daemon.notif
        backer: daemon
    }

    function handleDiscard() {
        if (!lock.retained) daemon.notif.dismiss();
        daemon.discarded();
    }

    function handleDismiss() {
    }

    RetainableLock {
        id: lock
        object: daemon.notif
        locked: true
        onRetainedChanged: {
            if (lock.retained) daemon.discard();
        }
    }

    expireTimeout: daemon.notif.expireTimeout
}
