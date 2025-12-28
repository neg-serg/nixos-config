pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import greeter

Item {
	id: root
	required property LockState state;

	property real focusAnim: root.focusAnimInternal * 0.001
	property int focusAnimInternal: Window.active ? 1000 : 0
	Behavior on focusAnimInternal { SmoothedAnimation { velocity: 5000 } }

	MouseArea {
		id: wakeupMouseArea
		anchors.fill: root
		hoverEnabled: true

		property real startMoveX: 0
		property real startMoveY: 0

		// prevents wakeups from bumping the mouse
		onPositionChanged: event => {
			if (root.state.fadedOut) {
				if (root.state.mouseMoved()) {
					const xOffset = Math.abs(event.x - wakeupMouseArea.startMoveX);
					const yOffset = Math.abs(event.y - wakeupMouseArea.startMoveY);
					const distanceSq = (xOffset * xOffset) + (yOffset * yOffset);
					if (distanceSq > (100 * 100)) root.state.fadeIn();
				} else {
					wakeupMouseArea.startMoveX = event.x;
					wakeupMouseArea.startMoveY = event.y;
				}
			}
		}

		Item {
			id: content
			width: wakeupMouseArea.width
			height: wakeupMouseArea.height
			y: root.state.fadeOutMul * (content.height / 2 + content.childrenRect.height)

			Rectangle {
				id: sep
				anchors.horizontalCenter: content.horizontalCenter
				y: (content.height - sep.height) / 2

				implicitHeight: 6
				implicitWidth: 800
				radius: sep.height / 2
				color: ShellGlobals.colors.widget
			}

			ColumnLayout {
				id: contentLayout
				implicitWidth: sep.implicitWidth
				anchors.horizontalCenter: content.horizontalCenter
				anchors.bottom: sep.top
				spacing: 0

				SystemClock {
					id: clock
					precision: SystemClock.Minutes
				}

				Text {
					id: timeText
					Layout.alignment: Qt.AlignHCenter

					font {
						pixelSize: 160
						hintingPreference: Font.PreferFullHinting
						family: "Iosevka"
					}

					color: "white"
					renderType: Text.NativeRendering

					text: {
						const hours = clock.hours.toString().padStart(2, '0');
						const minutes = clock.minutes.toString().padStart(2, '0');
						return `${hours}:${minutes}`;
					}
				}

				Item {
					id: textBoxWrapper
					Layout.alignment: Qt.AlignHCenter
					implicitHeight: textBox.height * root.focusAnim
					implicitWidth: sep.implicitWidth
					clip: true

					TextInput {
						id: textBox
						focus: true
						width: textBoxWrapper.width

						color: textBox.enabled ?
							root.state.failed ? "#ffa0a0" : "white"
							: "#80ffffff";

						font.pixelSize: 32
						font.family: "Iosevka"
						horizontalAlignment: TextInput.AlignHCenter
						echoMode: TextInput.Password
						inputMethodHints: Qt.ImhSensitiveData

						cursorVisible: textBox.text != ""
						onCursorVisibleChanged: textBox.cursorVisible = (textBox.text != "")

						onTextChanged: {
							root.state.currentText = textBox.text;
							textBox.cursorVisible = (textBox.text != "")
						}

						Window.onActiveChanged: {
							if (Window.active) {
								textBox.text = root.state.currentText;
							}
						}

						Connections {
							id: stateTextConnection
							target: root.state

							function onCurrentTextChanged() {
								textBox.text = root.state.currentText;
							}
						}

						onAccepted: {
							if (textBox.text != "") root.state.tryPasswordUnlock();
						}

						enabled: !root.state.isUnlocking;
					}

					Text {
						id: placeholderText
						anchors.fill: textBox
						font: textBox.font
						color: root.state.failed ? "#ffa0a0" : "#80ffffff";
						horizontalAlignment: Text.AlignHCenter
						visible: !textBox.cursorVisible
						text: root.state.failed ? root.state.error
							: root.state.fprintAvailable ? "Touch sensor or enter password" : "Enter password";
					}

					Rectangle {
						id: fprintStatus
						Layout.fillHeight: true
						implicitWidth: fprintStatus.height
						color: "transparent"
						visible: root.state.fprintAvailable

						anchors {
							right: textBox.right
							top: textBox.top
							bottom: textBox.bottom
						}

						Image {
							id: fprintIcon
							anchors.fill: fprintStatus
							anchors.margins: 5
							source: "root:icons/fingerprint.svg"
							sourceSize.width: fprintIcon.width
							sourceSize.height: fprintIcon.height
						}
					}
				}
			}

			Item {
				id: footerWrapper
				anchors.horizontalCenter: content.horizontalCenter
				anchors.top: sep.bottom
				implicitHeight: (75 + 30) * root.focusAnim
				implicitWidth: sep.implicitWidth
				clip: true

				RowLayout {
					id: footerLayout
					anchors.horizontalCenter: footerWrapper.horizontalCenter
					anchors.bottom: footerWrapper.bottom
					anchors.topMargin: 50
					spacing: 0

					LockButton {
						id: monitorButton
						icon: "root:icons/monitor.svg"
						onClicked: root.state.fadeOut();
					}

					LockButton {
						id: mediaPauseButton
						icon: "root:icons/pause.svg"
						show: root.state.mediaPlaying;
						onClicked: root.state.pauseMedia();
					}
				}
			}
		}
	}

	Rectangle {
		id: darkenOverlay
		anchors.fill: root
		color: "black"
		opacity: root.state.fadeOutMul
		visible: darkenOverlay.opacity != 0
	}
}
