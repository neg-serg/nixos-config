pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.lock as Lock

Item {
	id: root
	clip: true

	required property ShellScreen screen;
	property real slideAmount: 1.0 - Lock.Controller.bkgSlide
	property alias asynchronous: image.asynchronous;
	property string wallpaperPath: "file://" + (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/greeter-wallpaper";
	property string fallbackSource: Qt.resolvedUrl((root.screen?.name == "DP-1" ?? false) ? "5120x1728.png" : "1920x1296.png")
	property bool triedFallback: false;

	readonly property real remainingSize: image.height - root.height

	Image {
		id: image
		width: root.width
		height: root.width * (image.sourceSize.height / Math.max(image.sourceSize.width, 1))
		source: root.wallpaperPath
		y: -(root.slideAmount * root.remainingSize)

		onStatusChanged: {
			if (image.status === Image.Error && !root.triedFallback) {
				root.triedFallback = true;
				image.source = root.fallbackSource;
			}
		}
	}
}
