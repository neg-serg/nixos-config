pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.Notifications

TrackedNotification {
    id: daemon


    renderComponent: NotificationCard {
        notif: daemon
        backer: daemon
    }

    function handleDiscard() {
        if (!lock.retained) daemon.notif.dismiss();
        daemon.discarded();
    }

    function handleDismiss() {
        // Base TrackedNotification behavior: mark the tracked object discarded
        // so the manager removes it. The previous empty body left a dangling
        // backer.visualizer until the next notification.
        daemon.discard();
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
