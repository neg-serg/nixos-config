pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import qs

// The login card — the login screen of the single-compositor session and the
// lock screen of the shell. greeter/login.qml hosts it inside the session-lock
// surface and feeds the keyboard layout through layoutName/toggleLayout; the old
// greeter session (greeter.qml) reuses it with a GreeterContext instead.
//
// Screen layout: wallpaper → scrim → clock (upper third) → glass card with the
// avatar, the user name, the password field and the action row (layout chip on
// the left, screen-off / media / power on the right).
//
// Everything this file changes about the login phase is cosmetic: the state
// machine (LockState, the marker the layer writes, the fade-out to dpms off,
// the password field contents) is untouched.
Item {
	id: root
	required property LockState state;
	property GreeterContext context: null

	// Keyboard-layout chip: the login layer owns the compositor's layout (the
	// layer is what switches it), so it passes the current name and handles the
	// toggle. Empty in greeter mode, where the chip is not shown.
	property string layoutName: ""
	signal toggleLayout()

	// The wallpaper item (login.qml/greeter.qml): the glass shader samples it
	// behind the card. Null in a host without one — the card stays translucent.
	property Item backdrop: null

	// Whose session this is: the greeter context in greeter mode, $USER in the
	// single-compositor login (this process runs as the main user already).
	readonly property string userName: {
		if (root.context && root.context.currentUser)
		return root.context.currentUser;
		const user = Quickshell.env("USER");
		if (user)
		return user;
		return (Quickshell.env("HOME") || "").split("/").filter(part => part.length > 0).pop() || "";
	}
	readonly property string monogram: root.userName.length > 0 ? root.userName[0].toUpperCase() : "?"

	// Avatar: the theme's avatarPath (a circular PNG inside this tree — the login
	// phase runs before the home directory is deployed, so the image has to live in
	// the tree), then the usual ~/.face, then the monogram.
	property var avatarQueue: []
	property string avatarSource: ""

	function tryNextAvatar() {
		if (root.avatarQueue.length === 0)
		return;
		const next = root.avatarQueue[0];
		root.avatarQueue = root.avatarQueue.slice(1);
		root.avatarSource = next;
	}

	Component.onCompleted: {
		const home = Quickshell.env("HOME") || "";
		root.avatarQueue = [
		Qt.resolvedUrl("../" + GreeterTheme.avatarPath),
		"file://" + home + "/.face",
		"file://" + home + "/.config/quickshell/avatar.png",
		];
		root.tryNextAvatar();
	}

	property string hostName: ""
	FileView {
		id: hostNameView
		path: "/etc/hostname"
		blockLoading: false
		onLoaded: root.hostName = text().trim()
		onLoadFailed: root.hostName = ""
	}

	// Caps Lock cannot be read from QML, but the kernel exposes one LED per
	// keyboard that has it. A password typed in the wrong case is exactly the
	// failure this screen must not hide, so the field says it out loud.
	property bool capsLock: false
	property var capsPaths: []
	property var capsValues: ({})
	readonly property bool capsKnown: root.capsPaths.length > 0

	Process {
		id: capsProbe
		command: ["sh", "-c", "ls /sys/class/leds/*capslock*/brightness 2> /dev/null || true"]
		stdout: SplitParser {
			onRead: line => {
				const path = line.trim();
				if (path.length > 0)
				root.capsPaths = root.capsPaths.concat([path]);
			}
		}
		Component.onCompleted: running = true
	}

	Repeater {
		model: root.capsPaths

		Item {
			id: capsItem
			required property string modelData

			FileView {
				id: capsView
				path: capsItem.modelData
				watchChanges: true
				blockLoading: false
				onLoaded: root.noteCaps(capsItem.modelData, capsView.text())
				onFileChanged: reload()
			}
		}
	}

	function noteCaps(path, value) {
		const next = Object.assign({}, root.capsValues);
		next[path] = value.trim() === "1";

		root.capsValues = next;
		root.capsLock = Object.keys(next).some(key => next[key]);
	}

	// Clock line: the time from SystemClock, the date refreshed once a minute.
	SystemClock {
		id: clock
		precision: SystemClock.Minutes
	}

	// Time-of-day greeting under the date; the name is already on the card.
	readonly property string greeting: {
		const hour = clock.hours;
		if (hour >= 5 && hour < 12)
		return "Доброе утро";
		if (hour >= 12 && hour < 17)
		return "Добрый день";
		if (hour >= 17 && hour < 23)
		return "Добрый вечер";
		return "Доброй ночи";
	}

	property string dateText: ""
	Timer {
		interval: 60000
		running: true
		repeat: true
		triggeredOnStart: true
		onTriggered: {
			const locale = Qt.locale("ru_RU");
			const text = locale.toString(new Date(), "dddd, d MMMM");
			root.dateText = text.charAt(0).toUpperCase() + text.slice(1);
		}
	}

	// Focus drives the scrim: an unfocused screen (the compositor still starting
	// up, another window in front) reads as a background, not as a prompt.
	property real focusAnim: root.focusAnimInternal * 0.001
	property int focusAnimInternal: Window.active ? 1000 : 0
	Behavior on focusAnimInternal { SmoothedAnimation { velocity: 5000 } }

	// Entrance and failure feedback for the card.
	property real appearProgress: 0
	property real shakeOffset: 0
	Behavior on appearProgress {
		NumberAnimation {
			duration: GreeterTheme.appearMs
			easing.type: Easing.OutCubic
		}
	}
	SequentialAnimation {
		id: shake
		NumberAnimation { target: root; property: "shakeOffset"; to: -12; duration: 60 }
		NumberAnimation { target: root; property: "shakeOffset"; to: 12; duration: 90 }
		NumberAnimation { target: root; property: "shakeOffset"; to: -8; duration: 80 }
		NumberAnimation { target: root; property: "shakeOffset"; to: 8; duration: 80 }
		NumberAnimation { target: root; property: "shakeOffset"; to: 0; duration: 70 }
	}
	Connections {
		target: root.state
		function onFailedChanged() {
			if (root.state.failed)
			shake.restart();
		}
	}

	function powerAction(action) {
		power.run(action);
	}

	Process {
		id: power
		function run(action) {
			command = ["systemctl", action];
			running = true;
		}
	}

	// Wake-up on mouse movement while the screen is dark (dpms off), exactly as
	// before: the old behaviour is part of what the compositor does at login.
	// Everything visual lives inside `scene`: it is rendered once into a texture
	// and drawn through the CRT shader (below) instead of directly.
	Item {
		id: scene
		anchors.fill: parent

		MouseArea {
			id: wakeupMouseArea
			anchors.fill: parent
			hoverEnabled: true

			property real startMoveX: 0
			property real startMoveY: 0

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
		}

		Rectangle {
			id: scrim
			anchors.fill: parent
			color: "black"
			opacity: 0.24 + (0.26 * (1.0 - root.focusAnim))
		}

		// Vignette: the wallpaper darkens towards the corners, so the eye lands on the
		// clock and the card instead of the photo's own bright spots.
		Shape {
			anchors.fill: parent
			preferredRendererType: Shape.CurveRenderer

			ShapePath {
				strokeColor: "transparent"
				startX: 0
				startY: 0

				fillGradient: RadialGradient {
					centerX: root.width / 2
					centerY: root.height * 0.44
					centerRadius: Math.max(root.width, root.height) * 0.66
					focalX: centerX
					focalY: centerY

					GradientStop { position: 0.4; color: "transparent" }
					GradientStop { position: 1.0; color: "#96000000" }
				}

				PathRectangle {
					x: 0
					y: 0
					width: root.width
					height: root.height
				}
			}
		}

		Item {
			id: content
			anchors.fill: parent
			y: (root.height * 0.55) * root.state.fadeOutMul

			ColumnLayout {
				id: clockBlock
				anchors.horizontalCenter: parent.horizontalCenter
				anchors.top: parent.top
				anchors.topMargin: root.height * 0.11
				spacing: 4

				Text {
					id: timeText
					Layout.alignment: Qt.AlignHCenter

					font {
						pixelSize: 122
						hintingPreference: Font.PreferFullHinting
						family: "Iosevka"
					}

					color: GreeterTheme.textColor
					renderType: Text.NativeRendering
					style: Text.Outline
					styleColor: "#40000000"

					text: {
						const hours = clock.hours.toString().padStart(2, '0');
						const minutes = clock.minutes.toString().padStart(2, '0');
						return `${hours}:${minutes}`;
					}
				}

				Text {
					id: dateTextItem
					Layout.alignment: Qt.AlignHCenter

					font {
						pixelSize: 20
						hintingPreference: Font.PreferFullHinting
						family: "Iosevka"
					}

					color: GreeterTheme.textMutedColor
					renderType: Text.NativeRendering
					visible: text.length > 0
					text: root.dateText
				}

				Text {
					id: greetingText
					Layout.alignment: Qt.AlignHCenter
					Layout.topMargin: 6

					font {
						pixelSize: 19
						hintingPreference: Font.PreferFullHinting
						family: "Iosevka"
					}

					color: GreeterTheme.textColor
					opacity: 0.75
					renderType: Text.NativeRendering
					text: root.greeting
				}
			}

			// The minute change is the one thing on this screen that moves on its own;
			// a short fade keeps it from blinking.
			Connections {
				target: clock
				function onMinutesChanged() {
					minuteFlash.restart();
				}
			}

			NumberAnimation {
				id: minuteFlash
				target: timeText
				property: "opacity"
				from: 0.4
				to: 1.0
				duration: 500
				easing.type: Easing.OutCubic
			}

			Item {
				id: cardWrapper
				anchors.horizontalCenter: parent.horizontalCenter
				anchors.verticalCenter: parent.verticalCenter
				anchors.horizontalCenterOffset: root.shakeOffset
				anchors.verticalCenterOffset: (1.0 - root.appearProgress) * 18
				implicitWidth: card.implicitWidth
				implicitHeight: card.implicitHeight
				opacity: root.appearProgress

				// Frosted glass, drawn by shaders/glass_card.frag: the shader samples the
				// wallpaper behind the card (glassSource), blurs it, tints it, adds the sheen,
				// the grain and the drop shadow. Without a wallpaper item to sample (cage
				// mode) the plain translucent card below is what shows.
				ShaderEffect {
					id: glass
					anchors.fill: parent
					visible: root.backdrop !== null

					// Sampler for the shader must be called `source`.
					property Item source: glassSource
					property vector2d pCardSize: Qt.vector2d(glass.width, glass.height)
					property real pRadius: card.radius
					property real pBlur: GreeterTheme.glassBlur
					property color pTint: GreeterTheme.glassTint
					property real pHighlight: GreeterTheme.glassHighlight
					property real pRefract: GreeterTheme.glassRefract
					property real pShadow: GreeterTheme.glassShadow
					property real pGrain: GreeterTheme.glassGrain

					fragmentShader: Qt.resolvedUrl("../shaders/glass_card.frag.qsb")
				}

				// The padded wallpaper region the glass samples. The padding must match
				// the shader's own: pad = pBlur * 1.6 + 2.
			// A 1x1 stand-in keeps ShaderEffectSource happy when no wallpaper item was
			// handed in (cage mode) — the effect is hidden then anyway.
			Item {
				id: glassPlaceholder
				width: 1
				height: 1
				visible: false
			}

				ShaderEffectSource {
					id: glassSource
					sourceItem: root.backdrop !== null ? root.backdrop : glassPlaceholder
					hideSource: false
					live: true
					smooth: true
					sourceRect: {
						if (root.backdrop === null)
						return Qt.rect(0, 0, 1, 1);
						const pad = glass.pBlur * 1.6 + 2;
						const topLeft = glass.mapToItem(root.backdrop, -pad, -pad);
						return Qt.rect(topLeft.x, topLeft.y, glass.width + 2 * pad, glass.height + 2 * pad);
					}
				}

				Rectangle {
					id: card
					anchors.fill: parent
					implicitWidth: 470
					implicitHeight: cardLayout.implicitHeight + 64
					radius: 20
					color: root.backdrop !== null ? "transparent" : GreeterTheme.cardColor
					border.width: 1
					border.color: root.state.failed ? GreeterTheme.dangerColor
					: (textBox.activeFocus ? GreeterTheme.accentColor : GreeterTheme.cardOutline)

					Behavior on border.color {
						ColorAnimation {
							duration: GreeterTheme.animMediumMs
						}
					}

					// Soft top highlight — the sheen that reads as glass over a photo.
					Rectangle {
						anchors.top: parent.top
						anchors.left: parent.left
						anchors.right: parent.right
						anchors.margins: 1
						height: parent.radius
						radius: parent.radius - 1
						gradient: Gradient {
							GradientStop { position: 0.0; color: "#1affffff" }
							GradientStop { position: 1.0; color: "#00ffffff" }
						}
					}

					ColumnLayout {
						id: cardLayout
						anchors.fill: parent
						anchors.margins: 34
						spacing: 0

						Item {
							id: avatarBlock
							Layout.alignment: Qt.AlignHCenter
							Layout.bottomMargin: 18
							implicitWidth: 108
							implicitHeight: 108

							// The photo: a plain square image, cut into a disc by
							// shaders/avatar_round.frag (smooth rim, ring, halo). Hidden — the
							// shader draws it.
							Image {
								id: avatarPhoto
								anchors.fill: parent
								visible: false
								fillMode: Image.PreserveAspectCrop
								smooth: true
								source: root.avatarSource
								sourceSize.width: 512
								sourceSize.height: 512

								onStatusChanged: {
									if (avatarPhoto.status === Image.Error)
									root.tryNextAvatar();
								}
							}

							ShaderEffectSource {
								id: avatarTexture
								sourceItem: avatarPhoto
								hideSource: true
								live: true
								smooth: true
							}

							ShaderEffect {
								id: avatarDisc
								anchors.fill: parent
								visible: avatarPhoto.status === Image.Ready

								property Item source: avatarTexture
								property real pRingWidth: GreeterTheme.avatarRingWidth
								property color pRingColour: {
									const base = root.state.failed ? GreeterTheme.dangerColor
									: (root.state.isUnlocking ? GreeterTheme.accentColor : GreeterTheme.cardOutline);
									return Qt.rgba(base.r, base.g, base.b, root.state.isUnlocking ? 1.0 : 0.7);
								}
								property real pGlow: root.state.failed ? 0.0 : GreeterTheme.avatarGlow

								fragmentShader: Qt.resolvedUrl("../shaders/avatar_round.frag.qsb")

								Behavior on pGlow {
									NumberAnimation {
										duration: GreeterTheme.animSlowMs
									}
								}
							}

							// Monogram: the fallback when no avatar file can be read.
							Rectangle {
								id: monogram
								anchors.fill: parent
								radius: width / 2
								visible: avatarPhoto.status !== Image.Ready
								color: GreeterTheme.avatarColor
								border.width: 2
								border.color: root.state.failed ? GreeterTheme.dangerColor : GreeterTheme.cardOutline

								Text {
									anchors.centerIn: parent
									text: root.monogram
									color: GreeterTheme.textColor
									font.family: "Iosevka"
									font.pixelSize: 46
								}
							}

							Item {
								id: spinner
								anchors.fill: parent
								visible: root.state.isUnlocking

								RotationAnimation on rotation {
									running: spinner.visible
									loops: Animation.Infinite
									from: 0
									to: 360
									duration: 1100
								}

								Shape {
									anchors.fill: parent

									ShapePath {
										strokeColor: GreeterTheme.accentColor
										strokeWidth: 3
										fillColor: "transparent"
										capStyle: ShapePath.RoundCap

										PathAngleArc {
											centerX: spinner.width / 2
											centerY: spinner.height / 2
											radiusX: (spinner.width / 2) - 2
											radiusY: (spinner.height / 2) - 2
											startAngle: -90
											sweepAngle: 280
										}
									}
								}
							}
						}

						Text {
							id: nameText
							Layout.alignment: Qt.AlignHCenter
							text: root.userName
							color: GreeterTheme.textColor
							font.family: "Iosevka"
							font.pixelSize: 26
						}

						Text {
							id: hostText
							Layout.alignment: Qt.AlignHCenter
							Layout.topMargin: 2
							text: root.hostName
							color: GreeterTheme.textMutedColor
							font.family: "Iosevka"
							font.pixelSize: 16
							visible: text.length > 0
						}

						Rectangle {
							id: field
							Layout.alignment: Qt.AlignHCenter
							Layout.topMargin: 26
							implicitWidth: 384
							implicitHeight: 58
							radius: 13

							// Focus halo: a second outline a few pixels out, so the field
							// reads as active without a hard double border.
							Rectangle {
								id: fieldHalo
								anchors.fill: parent
								anchors.margins: -4
								radius: field.radius + 4
								color: "transparent"
								border.width: 2
								border.color: GreeterTheme.accentColor
								opacity: (textBox.activeFocus && !root.state.failed) ? 0.3 : 0.0

								Behavior on opacity {
									NumberAnimation {
										duration: GreeterTheme.animMediumMs
									}
								}
							}
							color: ShellGlobals.interpolateColors(0.55, "#00000000", ShellGlobals.colors.widget)
							border.width: 1
							border.color: root.state.failed ? GreeterTheme.dangerColor
							: (textBox.activeFocus ? GreeterTheme.accentColor : ShellGlobals.colors.widgetOutline)

							TextInput {
								id: textBox
								anchors.fill: parent
								anchors.leftMargin: field.radius + 12
								anchors.rightMargin: field.radius + 12
								focus: true

								color: {
									if (!textBox.enabled)
									return GreeterTheme.textMutedColor;
									return root.state.failed ? GreeterTheme.dangerColor : GreeterTheme.textColor;
								}

								font.pixelSize: 24
								font.family: "Iosevka"
								horizontalAlignment: TextInput.AlignHCenter
								verticalAlignment: TextInput.AlignVCenter
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

								enabled: !root.state.isUnlocking
							}

							Text {
								id: placeholderText
								anchors.fill: textBox
								font: textBox.font
								color: GreeterTheme.textMutedColor
								horizontalAlignment: Text.AlignHCenter
								verticalAlignment: Text.AlignVCenter
								visible: !textBox.cursorVisible
								text: textBox.enabled
								? (root.state.fprintAvailable ? "Коснитесь сенсора или введите пароль" : "Введите пароль")
								: "Проверка пароля…"
							}

							// PAM is running: a sweeping line along the field's bottom edge.
							Rectangle {
								id: fieldProgress
								anchors.left: parent.left
								anchors.right: parent.right
								anchors.bottom: parent.bottom
								anchors.leftMargin: 14
								anchors.rightMargin: 14
								anchors.bottomMargin: 4
								height: 2
								radius: 1
								color: "#26ffffff"
								visible: root.state.isUnlocking

								Rectangle {
									id: fieldProgressBar
									width: Math.max(28, fieldProgress.width * 0.3)
									height: parent.height
									radius: parent.radius
									color: GreeterTheme.accentColor

									NumberAnimation on x {
										running: fieldProgress.visible
										loops: Animation.Infinite
										from: -fieldProgressBar.width
										to: fieldProgress.width
										duration: 1100
									}
								}
							}

							// Fingerprint hint: the icon is the one the old field used.
							Image {
								anchors.right: parent.right
								anchors.verticalCenter: parent.verticalCenter
								anchors.rightMargin: 12
								width: 22
								height: 22
								visible: root.state.fprintAvailable
								source: "root:icons/fingerprint.svg"
								sourceSize.width: width
								sourceSize.height: height
								opacity: 0.6
							}
						}

						Text {
							id: capsHint
							Layout.alignment: Qt.AlignHCenter
							Layout.topMargin: 10
							text: "Caps Lock включён"
							color: GreeterTheme.dangerColor
							font.family: "Iosevka"
							font.pixelSize: 17
							visible: root.capsKnown && root.capsLock
						}

						Text {
							id: errorText
							Layout.alignment: Qt.AlignHCenter
							Layout.topMargin: 12
							text: root.state.error
							color: GreeterTheme.dangerColor
							font.family: "Iosevka"
							font.pixelSize: 16
							horizontalAlignment: Text.AlignHCenter
							visible: root.state.failed && text.length > 0
						}

						RowLayout {
							id: actionRow
							Layout.alignment: Qt.AlignHCenter
							Layout.topMargin: 22
							Layout.fillWidth: true
							spacing: 8

							Rectangle {
								id: layoutChip
								visible: root.layoutName.length > 0
								implicitWidth: layoutChipLabel.implicitWidth + 24
								implicitHeight: 40
								radius: 10
								color: ShellGlobals.interpolateColors(chipHover * 0.001, ShellGlobals.colors.widget, ShellGlobals.colors.widgetActive)
								border.width: 1
								border.color: ShellGlobals.colors.widgetOutline

								property int chipHover: chipMouse.containsMouse || chipMouse.pressed ? 1000 : 0
								Behavior on chipHover { SmoothedAnimation { velocity: 10000 } }

								Text {
									id: layoutChipLabel
									anchors.centerIn: parent
									text: "раскладка: " + root.layoutName
									color: GreeterTheme.textMutedColor
									font.family: "Iosevka"
									font.pixelSize: 15
								}

								MouseArea {
									id: chipMouse
									anchors.fill: parent
									hoverEnabled: true
									cursorShape: Qt.PointingHandCursor
									onClicked: root.toggleLayout()
								}
							}

							Item { Layout.fillWidth: true }

							PowerButton {
								id: monitorButton
								icon: "root:icons/monitor.svg"
								text: "Погасить экран"
								onClicked: root.state.fadeOut()
							}

							PowerButton {
								id: mediaPauseButton
								icon: "root:icons/pause.svg"
								text: "Пауза"
								visible: root.state.mediaPlaying
								onClicked: root.state.pauseMedia()
							}

							PowerButton {
								id: sleepButton
								icon: "root:icons/sleep.svg"
								text: "Спящий режим"
								onClicked: root.powerAction("suspend")
							}

							PowerButton {
								id: restartButton
								icon: "root:icons/restart.svg"
								text: "Перезагрузить"
								onClicked: root.powerAction("reboot")
							}

							PowerButton {
								id: powerButton
								icon: "root:icons/power.svg"
								text: "Выключить"
								onClicked: root.powerAction("poweroff")
							}
						}

						// User and session selector — the old greeter session only
						// (context is null in the single-compositor login).
						RowLayout {
							id: selectorRow
							Layout.alignment: Qt.AlignHCenter
							Layout.topMargin: 16
							spacing: 18
							visible: root.context !== null

							Text {
								id: userLabel
								color: GreeterTheme.textMutedColor
								font.pixelSize: 16
								font.family: "Iosevka"
								text: root.context ? root.context.currentUser : ""
								renderType: Text.NativeRendering

								MouseArea {
									anchors.fill: parent
									cursorShape: root.context && root.context.users.length > 1
									? Qt.PointingHandCursor : Qt.ArrowCursor
									onClicked: {
										if (root.context) root.context.cycleUser();
									}
								}
							}

							Text {
								color: GreeterTheme.textMutedColor
								opacity: 0.4
								font.pixelSize: 16
								font.family: "Iosevka"
								text: "|"
								renderType: Text.NativeRendering
							}

							Text {
								id: sessionLabel
								color: GreeterTheme.textMutedColor
								font.pixelSize: 16
								font.family: "Iosevka"
								text: root.context ? root.context.currentSessionName : ""
								renderType: Text.NativeRendering

								MouseArea {
									anchors.fill: parent
									cursorShape: root.context && root.context.sessions.length > 1
									? Qt.PointingHandCursor : Qt.ArrowCursor
									onClicked: {
										if (root.context) root.context.cycleSession();
									}
								}
							}
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

	// The CRT pass: barrel curve, chromatic aberration, scanlines, phosphor mask,
	// bloom, sweep and vignette — all in shaders/crt_screen.frag. crtEnabled=false
	// in the theme leaves the scene rendered directly.
	ShaderEffectSource {
		id: sceneTexture
		sourceItem: scene
		hideSource: GreeterTheme.crtEnabled
		live: true
	}

	ShaderEffect {
		id: crt
		anchors.fill: parent
		visible: GreeterTheme.crtEnabled

		property Item source: sceneTexture
		property real pScanCount: Math.max(80, crt.height / Math.max(GreeterTheme.crtLineSpacing, 1))
		property real pScanStrength: GreeterTheme.crtScanStrength
		property real pMaskStrength: GreeterTheme.crtMaskStrength
		property real pAberration: GreeterTheme.crtAberration
		property real pBarrel: GreeterTheme.crtBarrel
		property real pBloom: GreeterTheme.crtBloom
		property real pVignette: GreeterTheme.crtVignette
		property real pRollOffset: 0
		property real pRollStrength: GreeterTheme.crtRollStrength
		property real pFlicker: 1.0

		fragmentShader: Qt.resolvedUrl("../shaders/crt_screen.frag.qsb")

		NumberAnimation on pRollOffset {
			from: 0
			to: 1
			duration: Math.max(1500, GreeterTheme.crtRollMs)
			loops: Animation.Infinite
			running: crt.visible
		}

		// Irregular, small dips — a periodic flicker reads as a pulsing overlay.
		Timer {
			interval: 120
			running: crt.visible
			repeat: true
			onTriggered: crt.pFlicker = 0.9 + (Math.random() * 0.1)
		}
	}
}
