pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "screenshot" as Screenshot
import "bar" as Bar
import "lock" as Lock
import "notifications" as Notifs
import "launcher" as Launcher
import "background"

ShellRoot {
	id: root
	Component.onCompleted: [Lock.Controller, Launcher.Controller.init()]

	Process {
		id: mkdirProcess
		command: ["mkdir", "-p", ShellGlobals.rtpath]
		running: true
	}

	LazyLoader {
		id: screenshotLoader
		loading: true

		Screenshot.Controller {
			id: screenshotController
		}
	}

	Connections {
		id: ipcConnections
		target: ShellIpc

		function onScreenshot() {
			screenshotLoader.item.shooting = true;
		}
	}

	Notifs.NotificationOverlay {
		id: notifOverlay
		screen: Quickshell.screens.find(s => s.name === "DP-1") ?? Quickshell.screens[0]
	}

	Variants {
		id: screenVariants
		model: Quickshell.screens

		Scope {
			id: screenScope
			required property var modelData

			Bar.Bar {
				id: bar
				screen: screenScope.modelData
			}

			PanelWindow {
				id: window

				screen: screenScope.modelData

				exclusionMode: ExclusionMode.Ignore
				WlrLayershell.layer: WlrLayer.Background
				WlrLayershell.namespace: "shell:background"

				anchors {
					top: true
					bottom: true
					left: true
					right: true
				}

				BackgroundImage {
					id: bgImage
					anchors.fill: window
					screen: window.screen
				}
			}
		}
	}
}
