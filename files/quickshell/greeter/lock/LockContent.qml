pragma ComponentBehavior: Bound
import QtQuick
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
// Screen layout: wallpaper → scrim → clock (upper third) → card with the avatar,
// the `user@host` line, the password field, one status line and the action row
// (layout pill on the left, glyph buttons on the right).
//
// Look. The card is frosted glass (shaders/glass_card.frag) and draws no frame
// at all: no border, no second outline, no tooltip boxes. State is carried by
// the material and by type — the tint warms on a failure, the sheen lifts while
// the field has focus, the caret and the prompt glyph carry the accent. Nothing
// is ever drawn on top of the field, and the one line under it (statusLine)
// keeps its height whether or not it has something to say, so the card never
// changes size and never jumps.
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

	// Pointer position over the card and over the field (0..1 of each item): the
	// glass shader puts its highlight there, which is what makes the material feel
	// liquid instead of printed.
	property vector2d cardPointer: Qt.vector2d(0.5, 0.5)
	property vector2d fieldPointer: Qt.vector2d(0.5, 0.5)

	// One number scales every font size and the geometry around it.
	readonly property real uiScale: GreeterTheme.uiScale

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
		root.appearProgress = 1;
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

	// Entrance and failure feedback for the card. The shake is a nudge, not a
	// throw: it has to say "rejected" without moving the field under the cursor.
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
		NumberAnimation { target: root; property: "shakeOffset"; to: -5; duration: 55 }
		NumberAnimation { target: root; property: "shakeOffset"; to: 5; duration: 70 }
		NumberAnimation { target: root; property: "shakeOffset"; to: -3; duration: 60 }
		NumberAnimation { target: root; property: "shakeOffset"; to: 3; duration: 60 }
		NumberAnimation { target: root; property: "shakeOffset"; to: 0; duration: 55 }
	}
	Connections {
		target: root.state
		function onFailedChanged() {
			if (root.state.failed)
			shake.restart();
		}
	}

	// Hovered action button, named by the card's status line (PowerButton draws
	// no tooltip of its own, so nothing can end up on top of the field).
	property string hoveredAction: ""

	function noteHover(button, on) {
		if (on) {
			root.hoveredAction = button.text;
			return;
		}
		if (root.hoveredAction === button.text)
		root.hoveredAction = "";
	}

	// The five actions, in the order they sit on the right of the action row.
	readonly property var actionButtons: [
		{ glyph: "_", label: "Погасить экран", run: () => root.state.fadeOut() },
		{ glyph: "||", label: "Пауза", run: () => root.state.pauseMedia(), when: root.state.mediaPlaying },
		{ glyph: "z", label: "Спящий режим", run: () => root.powerAction("suspend") },
		{ glyph: "r", label: "Перезагрузить", run: () => root.powerAction("reboot") },
		{ glyph: "x", label: "Выключить", run: () => root.powerAction("poweroff") },
	]

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

	// The card's one line under the field: the failure first (it is why the
	// screen is still up), then Caps Lock, then whatever the pointer is over.
	readonly property string statusText: {
		if (root.state.failed && root.state.error.length > 0)
		return root.state.error;
		if (root.capsKnown && root.capsLock)
		return "Caps Lock включён";
		return root.hoveredAction;
	}
	readonly property color statusColour: (root.state.failed || (root.capsKnown && root.capsLock))
	? GreeterTheme.dangerColor : GreeterTheme.textMutedColor

	// The card's tint: plain glass, warm on a failure. Deriving it here keeps the
	// shader free of state and the card free of a red frame.
	readonly property color cardTint: root.state.failed
	? Qt.rgba(0.32, 0.11, 0.13, 0.44)
	: GreeterTheme.glassTint
	// Where the glass panes sample the wallpaper. The hosts hand in a backdrop
	// that fills the same surface as this item, so a pane's position inside it is
	// arithmetic — and it has to be arithmetic: QML does not track the property
	// reads a C++ call such as mapToItem() makes, so a sourceRect built around one
	// keeps the value it computed while the window was still 0x0 (the card sits at
	// (parent.width - width) / 2, i.e. at -width / 2 before the first layout, and
	// the field inside it). The panes then sampled a region a few hundred pixels
	// up and to the left — outside the wallpaper, where the texture is
	// transparent, and over its brightest part, which is the pale block that used
	// to sit on the right of the card. root.width/height are read on purpose: they
	// are the dependency that re-evaluates the origin when the surface resizes.
	readonly property point sampleOrigin: {
		const w = root.width;
		const h = root.height;
		if (root.backdrop === null || w <= 0 || h <= 0)
		return Qt.point(0, 0);
		return root.mapToItem(root.backdrop, 0, 0);
	}

	// The card's top-left in the backdrop's coordinates.
	readonly property real cardSampleX: root.sampleOrigin.x + content.x + cardWrapper.x
	readonly property real cardSampleY: root.sampleOrigin.y + content.y + cardWrapper.y

	// The field's top-left in the backdrop's coordinates: the card's, plus the
	// field's offset inside the card's layout.
	readonly property real fieldSampleX: root.cardSampleX + field.x
	readonly property real fieldSampleY: root.cardSampleY + field.y

	// Wake-up on mouse movement while the screen is dark (dpms off), exactly as
	// before: the old behaviour is part of what the compositor does at login.
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
			opacity: 0.18 + (0.22 * (1.0 - root.focusAnim))
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
					GradientStop { position: 1.0; color: "#78000000" }
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

				// The time is four gas-discharge tubes (lock/NixieClock.qml): glass that
				// refracts the wallpaper behind it, a wire cathode for every numeral and
				// a discharge that lights the tube it burns in.
				NixieClock {
					id: clockFace
					Layout.alignment: Qt.AlignHCenter
					hours: clock.hours
					minutes: clock.minutes
				}

				Text {
					id: dateTextItem
					Layout.alignment: Qt.AlignHCenter

					font {
						pixelSize: Math.round(20 * root.uiScale)
						hintingPreference: Font.PreferFullHinting
						family: GreeterTheme.uiFont
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
						pixelSize: Math.round(19 * root.uiScale)
						hintingPreference: Font.PreferFullHinting
						family: GreeterTheme.uiFont
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
				target: clockFace
				property: "opacity"
				from: 0.4
				to: 1.0
				duration: 500
				easing.type: Easing.OutCubic
			}

			Item {
				id: cardWrapper
				x: Math.round((parent.width - implicitWidth) / 2) + Math.round(root.shakeOffset)
				// Below the middle of the screen: the clock owns the upper third, the
				// card sits under it, and the gap that is left stays at the bottom
				// instead of being split evenly around a centred pane.
				y: Math.round((parent.height * 0.62) - (implicitHeight / 2)) + Math.round((1.0 - root.appearProgress) * 18)


				implicitWidth: card.implicitWidth
				implicitHeight: card.implicitHeight
				opacity: root.appearProgress

				// Hover-only: no button, so the field and the buttons above keep their clicks;
				// it only tells the glass where the light should be.
				MouseArea {
					id: cardPointerArea
					anchors.fill: parent
					hoverEnabled: true
					acceptedButtons: Qt.NoButton
					onPositionChanged: root.cardPointer = Qt.vector2d(x / width, y / height)
				}

				// Frosted glass, drawn by shaders/glass_card.frag: the shader samples the
				// wallpaper behind the card (glassSource), blurs it, tints it, adds the sheen,
				// the grain and the drop shadow. It also paints the pane's own edge, which is
				// why the card needs no border. Without a wallpaper item to sample (cage
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
					property color pTint: root.cardTint
					property real pHighlight: GreeterTheme.glassHighlight * (textBox.activeFocus ? 1.5 : 1.0)
					property real pRefract: GreeterTheme.glassRefract
					property real pShadow: GreeterTheme.glassShadow
					property real pGrain: GreeterTheme.glassGrain
					property real pLens: GreeterTheme.glassLens
					property real pChroma: GreeterTheme.glassChroma
					property real pSpecular: GreeterTheme.glassSpecular * (textBox.activeFocus ? 1.3 : 1.0)
					property real pPointerStrength: GreeterTheme.glassPointer
					property vector2d pPointer: root.cardPointer

					fragmentShader: Qt.resolvedUrl("../shaders/glass_card.frag.qsb")

					Behavior on pTint {
						ColorAnimation {
							duration: GreeterTheme.animMediumMs
						}
					}
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
					// live: the wallpaper is decoded asynchronously — the login layer
					// hands the pane a backdrop that is still empty when the card is
					// already on screen, and a cached sample would keep that emptiness.
					// The region is the pane's own, so this is a small capture, not the
					// whole screen.
					live: true



					smooth: true
					sourceRect: {
						if (root.backdrop === null)
						return Qt.rect(0, 0, 1, 1);
						const pad = glass.pBlur * 1.6 + 2;
						return Qt.rect(root.cardSampleX - pad, root.cardSampleY - pad,
						glass.width + 2 * pad, glass.height + 2 * pad);
					}
				}

				Rectangle {
					id: card
					anchors.fill: parent
					implicitWidth: Math.round(480 * root.uiScale)
					implicitHeight: cardLayout.implicitHeight + Math.round(64 * root.uiScale)
					radius: GreeterTheme.cardRadius
					// No border: the glass shader paints the rim, and on a failure the
					// tint above says what happened. A 1px frame over a photo only adds
					// a second edge for the eye to trip over.
					color: root.backdrop !== null ? "transparent" : GreeterTheme.cardColor

					ColumnLayout {
						id: cardLayout
						anchors.fill: parent
						anchors.margins: Math.round(30 * root.uiScale)
						spacing: 0

						Item {
							id: avatarBlock
							Layout.alignment: Qt.AlignHCenter
							Layout.bottomMargin: Math.round(16 * root.uiScale)
							implicitWidth: Math.round(104 * root.uiScale)
							implicitHeight: Math.round(104 * root.uiScale)

							// The photo: a plain image, framed by
							// shaders/avatar_frame.frag (rounded square, ring, halo). Hidden — the
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
								live: false
								smooth: true
							}

							ShaderEffect {
								id: avatarDisc
								anchors.fill: parent
								visible: avatarPhoto.status === Image.Ready

								property Item source: avatarTexture
								property real pRadius: GreeterTheme.avatarRadius
								property real pRingWidth: GreeterTheme.avatarRingWidth
								property color pRingColour: {
									const base = root.state.failed ? GreeterTheme.dangerColor
									: (root.state.isUnlocking ? GreeterTheme.accentColor : GreeterTheme.cardOutline);
									return Qt.rgba(base.r, base.g, base.b, root.state.isUnlocking ? 1.0 : 0.55);
								}
								property real pGlow: root.state.failed ? 0.0 : GreeterTheme.avatarGlow

								fragmentShader: Qt.resolvedUrl("../shaders/avatar_frame.frag.qsb")

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
								radius: GreeterTheme.avatarRadius
								visible: avatarPhoto.status !== Image.Ready
								color: GreeterTheme.avatarColor

								Text {
									renderType: Text.NativeRendering
									anchors.centerIn: parent
									text: root.monogram
									color: GreeterTheme.textColor
									font.family: GreeterTheme.uiFont
									font.hintingPreference: Font.PreferFullHinting
									font.pixelSize: Math.round(46 * root.uiScale)
								}
							}

						}

						// `user@host`, the way a prompt writes it. One line: the name
						// and the machine belong together, and two centred lines under
						// the avatar only made the card taller.
						RowLayout {
							id: identityRow
							Layout.alignment: Qt.AlignHCenter
							spacing: 0

							Text {
								renderType: Text.NativeRendering
								id: nameText
								text: root.userName
								color: GreeterTheme.textColor
								font.family: GreeterTheme.uiFont
								font.hintingPreference: Font.PreferFullHinting
								font.pixelSize: Math.round(22 * root.uiScale)
							}

							Text {
								renderType: Text.NativeRendering
								id: hostText
								text: root.hostName.length > 0 ? "@" + root.hostName : ""
								color: GreeterTheme.textMutedColor
								opacity: 0.6
								font.family: GreeterTheme.uiFont
								font.hintingPreference: Font.PreferFullHinting
								font.pixelSize: Math.round(22 * root.uiScale)
								visible: text.length > 0
							}
						}

						// The field. A dark glass slab with no frame of its own: the
						// prompt glyph, the caret and the placeholder say "type here",
						// and the shader's rim does the rest.
						Item {
							id: field
							Layout.alignment: Qt.AlignHCenter
							Layout.topMargin: Math.round(22 * root.uiScale)
							implicitWidth: Math.round(384 * root.uiScale)
							implicitHeight: Math.round(58 * root.uiScale)

							// Flat fallback for a host with no wallpaper to sample.
							Rectangle {
								anchors.fill: parent
								radius: GreeterTheme.fieldRadius
								color: ShellGlobals.interpolateColors(0.55, "#00000000", ShellGlobals.colors.widget)
								visible: root.backdrop === null
							}

							ShaderEffect {
								id: fieldGlass
								anchors.fill: parent
								visible: root.backdrop !== null

								property Item source: fieldGlassSource
								property vector2d pCardSize: Qt.vector2d(fieldGlass.width, fieldGlass.height)
								property real pRadius: GreeterTheme.fieldRadius
								property real pBlur: GreeterTheme.fieldBlur
								property color pTint: GreeterTheme.fieldTint
								property real pHighlight: 0.035
								property real pRefract: 4
								property real pShadow: 0
								property real pGrain: 0.012
								property real pLens: GreeterTheme.glassLens * 0.4
								property real pChroma: GreeterTheme.glassChroma
								property real pSpecular: GreeterTheme.glassSpecular * (textBox.activeFocus ? 1.6 : 0.8)
								property real pPointerStrength: textBox.activeFocus ? GreeterTheme.glassPointer : 0.0
								property vector2d pPointer: root.fieldPointer

								fragmentShader: Qt.resolvedUrl("../shaders/glass_card.frag.qsb")
							}

							ShaderEffectSource {
								id: fieldGlassSource
								sourceItem: root.backdrop !== null ? root.backdrop : glassPlaceholder
								hideSource: false
								// live for the same reason as the card's pane: the sample has to
								// follow a wallpaper that is still decoding.
								live: true
								smooth: true
								sourceRect: {
									if (root.backdrop === null)
									return Qt.rect(0, 0, 1, 1);
									const pad = GreeterTheme.fieldBlur * 1.6 + 2;
									return Qt.rect(root.fieldSampleX - pad, root.fieldSampleY - pad,
									fieldGlass.width + 2 * pad, fieldGlass.height + 2 * pad);
								}
							}

							MouseArea {
								id: fieldPointerArea
								anchors.fill: parent
								hoverEnabled: true
								acceptedButtons: Qt.NoButton
								onPositionChanged: root.fieldPointer = Qt.vector2d(x / width, y / height)
							}

							// The prompt: a terminal hands the line over with one of these.
							Text {
								id: promptText
								anchors.left: parent.left
								anchors.leftMargin: Math.round(18 * root.uiScale)
								anchors.verticalCenter: parent.verticalCenter
								renderType: Text.NativeRendering
								text: ">"
								color: GreeterTheme.accentColor
								opacity: textBox.activeFocus ? 0.9 : 0.35
								font.family: GreeterTheme.uiFont
								font.hintingPreference: Font.PreferFullHinting
								font.pixelSize: Math.round(20 * root.uiScale)

								Behavior on opacity {
									NumberAnimation {
										duration: GreeterTheme.animMediumMs
									}
								}
							}

							TextInput {
								id: textBox
								anchors.fill: parent
								anchors.leftMargin: Math.round(42 * root.uiScale)
								anchors.rightMargin: fingerprintIcon.visible ? Math.round(46 * root.uiScale) : Math.round(18 * root.uiScale)
								focus: true

								color: {
									if (!textBox.enabled)
									return GreeterTheme.textMutedColor;
									return root.state.failed ? GreeterTheme.dangerColor : GreeterTheme.textColor;
								}

								font.pixelSize: Math.round(22 * root.uiScale)
								font.family: GreeterTheme.uiFont
								font.hintingPreference: Font.PreferFullHinting
								font.letterSpacing: 2
								verticalAlignment: TextInput.AlignVCenter
								// Left-aligned, the way a line of input is read; the dots
								// get room to breathe instead of running into each other.
								horizontalAlignment: TextInput.AlignLeft
								echoMode: TextInput.Password
								passwordCharacter: "•"
								inputMethodHints: Qt.ImhSensitiveData

								// The caret is the block cursor of a terminal (kitty runs a block with no
								// blink — files/kitty/kitty.conf), not a hairline: one cell wide, filled
								// with the accent, with the character it covers drawn *inside* it in the
								// colour of the field. A terminal inverts the cell the cursor sits on, and
								// on a password that is not a detail — a plain block over a dot hides one
								// character and the dots stop counting.
								cursorDelegate: Item {
									id: caret

									width: Math.round(caretMetrics.advanceWidth)
									height: Math.round(24 * root.uiScale)
									// The field shows its hint while it is empty, and the block would sit on
									// the first letter of it: the cursor arrives with the first character
									// typed. Qt turns cursorVisible back on by itself when the window is
									// activated, so the delegate is what decides.
									opacity: textBox.text.length > 0 ? 1.0 : 0.0

									// The same font as the field, so the block is exactly as wide as the
									// character it sits on.
									TextMetrics {
										id: caretMetrics
										font: textBox.font
										text: textBox.passwordCharacter
									}

									// The block lights the glass around it, the way the tubes above light
									// theirs.
									Rectangle {
										anchors.centerIn: parent
										width: parent.width + Math.round(7 * root.uiScale)
										height: parent.height + Math.round(5 * root.uiScale)
										radius: Math.round(4 * root.uiScale)
										color: GreeterTheme.accentColor
										opacity: 0.16
									}

									Rectangle {
										anchors.fill: parent
										radius: Math.round(2 * root.uiScale)
										color: GreeterTheme.accentColor
									}

									Text {
										anchors.centerIn: parent

										// The character the cursor sits on, drawn inside the block. At the
										// end of the line there is none — the cursor is past the last dot,
										// and a block that invented one would add a character to the
										// password.
										visible: textBox.cursorPosition < textBox.text.length
										text: textBox.passwordCharacter
										color: GreeterTheme.fieldTint
										renderType: Text.NativeRendering
										font: textBox.font
									}
								}
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

							// The placeholder sits where the text will be, in the body
							// font and a size below it: it used to be a full line of
							// 29px monospace, wider than the field it was drawn in.
							Text {
								renderType: Text.NativeRendering
								id: placeholderText
								anchors.left: promptText.right
								anchors.leftMargin: Math.round(12 * root.uiScale)
								anchors.right: fingerprintIcon.visible ? fingerprintIcon.left : parent.right
								anchors.rightMargin: Math.round(14 * root.uiScale)
								anchors.verticalCenter: parent.verticalCenter
								elide: Text.ElideRight
								font.family: GreeterTheme.uiFont
								font.hintingPreference: Font.PreferFullHinting
								font.pixelSize: Math.round(17 * root.uiScale)
								// Caps, and a step up in weight: this is an instruction, not a
								// caption, and it has to read at a glance over any wallpaper.
								font.weight: Font.Medium
								font.capitalization: Font.AllUppercase
								color: GreeterTheme.textMutedColor
								opacity: 0.7
								visible: textBox.text === ""
								text: textBox.enabled
								? (root.state.fprintAvailable ? "коснитесь сенсора или введите пароль" : "введите пароль")
								: "проверка пароля…"
							}

							// PAM is running: a lone accent line sweeping along the bottom
							// edge of the field. No track, no box.
							Item {
								id: fieldProgress
								anchors.left: parent.left
								anchors.right: parent.right
								anchors.bottom: parent.bottom
								anchors.leftMargin: Math.round(14 * root.uiScale)
								anchors.rightMargin: Math.round(14 * root.uiScale)
								anchors.bottomMargin: Math.round(8 * root.uiScale)
								height: 2
								visible: root.state.isUnlocking

								Rectangle {
									id: fieldProgressBar
									width: Math.max(24, fieldProgress.width * 0.35)
									height: parent.height
									radius: height / 2
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
								id: fingerprintIcon
								anchors.right: parent.right
								anchors.verticalCenter: parent.verticalCenter
								anchors.rightMargin: Math.round(16 * root.uiScale)
								width: Math.round(22 * root.uiScale)
								height: width
								visible: root.state.fprintAvailable
								source: "root:icons/fingerprint.svg"
								sourceSize.width: width
								sourceSize.height: height
								opacity: 0.45
							}
						}

						// One line for everything the card has to say, and it keeps its
						// height when it says nothing: a card that grows a row on a typo
						// moves the field out from under the pointer.
						Item {
							id: statusLine
							Layout.fillWidth: true
							Layout.topMargin: Math.round(10 * root.uiScale)
							implicitHeight: Math.round(24 * root.uiScale)

							Text {
								renderType: Text.NativeRendering
								id: statusLabel
								anchors.fill: parent
								text: root.statusText
								color: root.statusColour
								opacity: text.length > 0 ? 1.0 : 0.0
								elide: Text.ElideRight
								horizontalAlignment: Text.AlignHCenter
								verticalAlignment: Text.AlignVCenter
								font.family: GreeterTheme.uiFont
								font.hintingPreference: Font.PreferFullHinting
								font.pixelSize: Math.round(16 * root.uiScale)

								Behavior on opacity {
									NumberAnimation {
										duration: GreeterTheme.animFastMs
									}
								}
							}
						}

						// Layout pill on the left, the action glyphs on the right. The
						// buttons are a row — inside the column layout each one used to
						// become a row of its own and stack down the card.
						RowLayout {
							id: actionRow
							Layout.alignment: Qt.AlignHCenter
							Layout.fillWidth: true
							Layout.topMargin: Math.round(14 * root.uiScale)
							spacing: Math.round(6 * root.uiScale)

							Rectangle {
								id: layoutChip
								Layout.alignment: Qt.AlignVCenter | Qt.AlignLeft
								visible: root.layoutName.length > 0
								implicitWidth: layoutChipLabel.implicitWidth + Math.round(26 * root.uiScale)
								implicitHeight: Math.round(32 * root.uiScale)
								// A pill, and no border: hover only deepens the fill.
								radius: height / 2
								color: ShellGlobals.interpolateColors(chipHover * 0.001, "#14ffffff", ShellGlobals.colors.widgetActive)

								property int chipHover: chipMouse.containsMouse || chipMouse.pressed ? 1000 : 0
								Behavior on chipHover { SmoothedAnimation { velocity: 10000 } }

								Text {
									renderType: Text.NativeRendering
									id: layoutChipLabel
									anchors.centerIn: parent
									text: "раскладка: " + root.layoutName
									color: GreeterTheme.textMutedColor
									font.family: GreeterTheme.uiFont
									font.hintingPreference: Font.PreferFullHinting
									font.pixelSize: Math.round(15 * root.uiScale)
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

							Repeater {
								model: root.actionButtons

								PowerButton {
									required property var modelData

									Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
									glyph: modelData.glyph
									text: modelData.label
									visible: modelData.when === undefined || modelData.when
									onClicked: modelData.run()
									onHoveredChanged: root.noteHover(this, hovered)
								}
							}
						}

						// User and session selector — the old greeter session only
						// (context is null in the single-compositor login).
						RowLayout {
							id: selectorRow
							Layout.alignment: Qt.AlignHCenter
							Layout.topMargin: Math.round(10 * root.uiScale)
							spacing: 18
							visible: root.context !== null

							Text {
								renderType: Text.NativeRendering
								id: userLabel
								color: GreeterTheme.textMutedColor
								font.pixelSize: Math.round(16 * root.uiScale)
								font.family: GreeterTheme.uiFont
								font.hintingPreference: Font.PreferFullHinting
								text: root.context ? root.context.currentUser : ""

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
								renderType: Text.NativeRendering
								color: GreeterTheme.textMutedColor
								opacity: 0.4
								font.pixelSize: Math.round(16 * root.uiScale)
								font.family: GreeterTheme.uiFont
								font.hintingPreference: Font.PreferFullHinting
								text: "|"
							}

							Text {
								renderType: Text.NativeRendering
								id: sessionLabel
								color: GreeterTheme.textMutedColor
								font.pixelSize: Math.round(16 * root.uiScale)
								font.family: GreeterTheme.uiFont
								font.hintingPreference: Font.PreferFullHinting
								text: root.context ? root.context.currentSessionName : ""

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
			anchors.fill: parent
			color: "black"
			opacity: root.state.fadeOutMul
			visible: darkenOverlay.opacity != 0
		}
	}

	// Scanlines over the UI too, but nothing else: no warp, no bloom, no resample,
	// so the card and its text stay exact while the screen still reads as a tube.
	CrtBackdrop {
		anchors.fill: parent
		visible: GreeterTheme.crtEnabled && GreeterTheme.crtUiLines > 0.001
		pScanStrength: GreeterTheme.crtUiLines
		pMaskStrength: 0
		pVignette: 0
		pRollStrength: 0
		pLinesOnly: 1
	}

}
