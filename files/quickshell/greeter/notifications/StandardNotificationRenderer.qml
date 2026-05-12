pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Services.Notifications
import qs

Rectangle {
	id: root
	required property Notification notif;
	required property var backer;

	color: root.notif.urgency === NotificationUrgency.Critical ? "#30ff2030" : "#30c0ffff"
	radius: 5
	implicitWidth: 450
	implicitHeight: mainLayout.implicitHeight

	HoverHandler {
		id: hoverHandler
		onHoveredChanged: {
			root.backer.pauseCounter += (hoverHandler.hovered ? 1 : -1);
		}
	}

	Rectangle {
		id: borderRect
		anchors.fill: root
		color: "transparent"
		border.width: 2
		border.color: ShellGlobals.colors.widgetOutline
		radius: root.radius
	}

	ColumnLayout {
		id: mainLayout
		anchors.fill: root
		spacing: 0

		ColumnLayout {
			id: contentLayout
			Layout.margins: 10

			RowLayout {
				id: headerLayout
				Image {
					id: appIconImage
					visible: appIconImage.source !== ""
					source: root.notif.appIcon ? Quickshell.iconPath(root.notif.appIcon) : ""
					fillMode: Image.PreserveAspectFit
					antialiasing: true
					sourceSize.width: 30
					sourceSize.height: 30
					Layout.preferredWidth: 30
					Layout.preferredHeight: 30
				}

				Label {
					id: summaryLabel
					visible: summaryLabel.text !== ""
					text: root.notif.summary
					font.pointSize: 20
					elide: Text.ElideRight
					Layout.maximumWidth: root.implicitWidth - 100 // QTBUG-127649
				}

				Item { id: headerSpacer; Layout.fillWidth: true }

				MouseArea {
					id: closeArea
					Layout.preferredWidth: 30
					Layout.preferredHeight: 30

					hoverEnabled: true
					onPressed: root.backer.discard();

					Rectangle {
						id: closeBackground
						anchors.fill: closeArea
						anchors.margins: 5
						radius: closeBackground.width * 0.5
						antialiasing: true
						color: "#60ffffff"
						opacity: closeArea.containsMouse ? 1 : 0
						Behavior on opacity { SmoothedAnimation { velocity: 8 } }
					}

					CloseButton {
						id: closeButton
						anchors.fill: closeArea
						ringFill: root.backer.timePercentage
					}
				}
			}

			Item {
				id: bodyWrapper
				Layout.topMargin: 3
				visible: bodyLabel.text !== "" || notifImage.visible
				implicitWidth: bodyLabel.width
				implicitHeight: Math.max(notifImage.size, bodyLabel.implicitHeight)

				Image {
					id: notifImage
					readonly property int size: notifImage.visible ? 14 * 8 : 0
					y: bodyLabel.y + bodyLabel.topPadding

					visible: notifImage.source !== ""
					source: root.notif.image
					fillMode: Image.PreserveAspectFit
					cache: false
					antialiasing: true

					width: notifImage.size
					height: notifImage.size
					sourceSize.width: notifImage.size
					sourceSize.height: notifImage.size
				}

				Label {
					id: bodyLabel
					width: root.implicitWidth - 20
					text: root.notif.body
					wrapMode: Text.Wrap

					onLineLaidOut: line => {
						if (!notifImage.visible) return;

						const isize = notifImage.size + 6;
						if (line.y + line.height <= notifImage.y + isize) {
							line.x += isize;
							line.width -= isize;
						}
					}
				}
			}
		}

		ColumnLayout {
			id: actionsLayout
			Layout.fillWidth: true
			Layout.margins: borderRect.border.width
			spacing: 0
			visible: root.notif.actions.length !== 0

			Rectangle {
				id: actionsSeparator
				height: borderRect.border.width
				Layout.fillWidth: true
				color: borderRect.border.color
				antialiasing: true
			}

			RowLayout {
				id: actionsRow
				spacing: 0

				Repeater {
					id: actionsRepeater
					model: root.notif.actions

					Item {
						id: actionDelegate
						required property NotificationAction modelData;
						required property int index;

						Layout.fillWidth: true
						implicitHeight: 35

						Rectangle {
							id: actionSeparator
							anchors {
								top: actionDelegate.top
								bottom: actionDelegate.bottom
								left: actionDelegate.left
								leftMargin: -actionSeparator.implicitWidth * 0.5
							}

							visible: actionDelegate.index !== 0
							implicitWidth: borderRect.border.width
							color: ShellGlobals.colors.widgetOutline
							antialiasing: true
						}

						MouseArea {
							id: actionArea
							anchors.fill: actionDelegate

							onClicked: {
								actionDelegate.modelData.invoke();
							}

							Rectangle {
								id: actionPressHighlight
								anchors.fill: actionArea
								color: actionArea.pressed && actionArea.containsMouse ? "#20000000" : "transparent"
							}

							RowLayout {
								id: actionContent
								anchors.centerIn: actionArea

								Image {
									id: actionIcon
									visible: root.notif.hasActionIcons
									source: Quickshell.iconPath(actionDelegate.modelData.identifier)
									fillMode: Image.PreserveAspectFit
									antialiasing: true
									sourceSize.height: 25
									sourceSize.width: 25
								}

								Label {
									id: actionLabel
									text: actionDelegate.modelData.text
								}
							}
						}
					}
				}
			}
		}
	}
}
