pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// NotificationDisplay — simplified notification stack (no ZHVStack / shader mask).
// Replaces the greeter's complex FlickableNotification-based display with a
// dunst-like ColumnLayout stack: notifications fade in/out, auto-dismiss on
// expiry, and stack downward from the anchor edge.

Item {
    id: root
    property list<Item> notifications: [];

    // NotificationCard component factory
    property Component notifCardComponent: NotificationCard {}

    function addNotification(notification) {
        console.log("[Display] addNotification:", notification.notif.summary, "notifications:", root.notifications.length);
        const harness = harnessComponent.createObject(contentCol, {
            backer: notification,
        });
        if (!harness) return null;
        harness.contentItem = root.notifCardComponent.createObject(harness, {
            notif: notification.notif,
            backer: notification,
        });
        root.notifications = [...root.notifications, harness];
        console.log("[Display] card created, w:", harness.contentItem.width, "h:", harness.contentItem.height);

        // Enforce max toast count — dismiss oldest if exceeding
        var active = root.notifications.filter(function(h) { return h && !h._dismissed; });
        if (active.length > NotificationManager.maxToastCount) {
            var oldest = active[0];
            if (oldest && oldest.canDismiss)
                oldest.dismiss();
        }

        return harness;
    }

    // addSet — called when notification center opens; brings back history notifications
    function addSet(notifications) {
        let delay = 0;
        for (const n of notifications) {
            if (n.visualizer) continue; // already has harness
            const harness = root.addNotification(n);
            harness.playEntry(delay);
            delay += 25;
        }
    }

    function dismissAll() {
        let delay = 0;
        for (const n of root.notifications) {
            if (!n || n._dismissed) continue;
            n.dismissDelay(delay);
            delay += 25;
        }
    }

    function discardAll() {
        let delay = 0;
        for (const n of root.notifications) {
            if (!n || n._dismissed) continue;
            n.discardDelay(delay);
            delay += 25;
        }
    }

    // ── Notification stack (bottom-anchored via top spacer) ────────
    ColumnLayout {
        id: contentCol
        anchors.fill: parent
        spacing: 4

        // Pushes notifications to the bottom edge
        Item { Layout.fillHeight: true }
    }
    Component {
        id: harnessComponent

        Item {
            id: harness
            required property var backer;
            property Item contentItem;
            property bool _dismissed: false;
            property bool canDismiss: !harness._dismissed;
            property real _contentOpacity: 1.0;

            implicitWidth: contentItem ? contentItem.width : 0
            implicitHeight: contentItem ? contentItem.height * harness._contentOpacity : 0
            Layout.alignment: Qt.AlignRight

            property int _expireMs: (harness.backer && harness.backer.expireTimeout > 0)
                ? harness.backer.expireTimeout : 5000

            // ── Animations (declared before onCompleted) ───────────
            NumberAnimation {
                id: fadeIn
                target: harness; property: "_contentOpacity"
                from: 0; to: 1; duration: 200
            }

            NumberAnimation {
                id: fadeOut
                target: harness; property: "_contentOpacity"
                from: 1; to: 0; duration: 200
                onStopped: harness.finishDismiss()
            }

            Timer {
                id: expireTimer
                interval: harness._expireMs
                repeat: false
                running: harness._expireMs > 0 && harness.backer
                    && harness.backer.notif && harness.backer.notif.urgency !== 2
                onTriggered: harness.dismiss()
            }

            Timer {
                id: fadeInStop
                interval: 1
                onTriggered: { fadeIn.stop(); harness._contentOpacity = 0; fadeIn.start(); }
            }

            Timer {
                id: delayTimer
                property var triggerFunc: null
                onTriggered: { if (triggerFunc) triggerFunc(); }
            }

            // ── Lifecycle connections (discard signal exists on TrackedNotification) ──
            Connections {
                target: harness.backer
                function onDiscard() { harness.discard(); }
            }

            Component.onCompleted: {
                if (harness.backer) harness.backer.visualizer = harness;
                harness._contentOpacity = 0;
                fadeIn.start();
            }

            function playEntry(delayMs) {
                fadeInStop.restart();
            }

            function dismissDelay(ms) {
                delayTimer.interval = ms;
                delayTimer.triggerFunc = function() { harness.dismiss(); };
                delayTimer.restart();
            }

            function discardDelay(ms) {
                delayTimer.interval = ms;
                delayTimer.triggerFunc = function() { harness.discard(); };
                delayTimer.restart();
            }

            function dismiss() {
                if (harness._dismissed) return;
                harness._dismissed = true;
                harness.backer.handleDismiss();
                fadeOut.start();
            }

            function discard() {
                if (harness._dismissed) return;
                harness._dismissed = true;
                harness.backer.handleDiscard();
                fadeOut.start();
            }

            function finishDismiss() {
                root.notifications = root.notifications.filter(function(h) { return h !== harness; });
                harness.destroy();
            }
        }
    }
}
