pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "../components"

ShellRoot {
	id: root

	Component {
		id: demoNotif

		FlickableNotification {
			id: flickableNotif
			contentItem: Rectangle {
				id: contentRect
				color: "white"
				border.color: "blue"
				border.width: 2
				radius: 10
				width: 400
				height: 150
			}

			onLeftViewBounds: flickableNotif.destroy()
		}
	}

	property Component testComponent: TrackedNotification {
		id: notification

		renderComponent: Rectangle {
			id: renderRect
			color: "white"
			border.color: "blue"
			border.width: 2
			radius: 10
			width: 400
			height: 150

			ColumnLayout {
				id: buttonColumn
				Button {
					id: dismissButton
					text: "dismiss"
					onClicked: notification.dismiss();
				}

				Button {
					id: discardButton
					text: "discard"
					onClicked: notification.discard();
				}
			}
		}

		function handleDismiss() {
			console.log(`dismiss (sub)`)
		}

		function handleDiscard() {
			console.log(`discard (sub)`)
		}

		Component.onDestruction: console.log(`destroy (sub)`)
	};

	property Component realComponent: DaemonNotification {
		id: dn
	}

	NotificationServer {
		id: notificationServer
		onNotification: notification => {
			notification.tracked = true;

			const o = root.realComponent.createObject(null, { notif: notification });
			display.addNotification(o);
		}
	}

	FloatingWindow {
		id: testWindow
		color: "transparent"

		ColumnLayout {
			id: mainLayout
			x: 5

			Button {
				id: addNotifButton
				visible: false
				text: "add notif"

				onClicked: {
					const notif = root.testComponent.createObject(null);
					display.addNotification(notif);
				}
			}

			NotificationDisplay { id: display }
		}
	}
}
