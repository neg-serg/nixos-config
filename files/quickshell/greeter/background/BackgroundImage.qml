pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import greeter.lock as Lock

Item {
	id: root

	required property ShellScreen screen;
	property real slideAmount: 1.0 - Lock.Controller.bkgSlide
	property alias asynchronous: image.asynchronous;
	property string wallpaperPath: "file:///var/lib/greetd/wallpaper.jpg";
	property string fallbackSource: Qt.resolvedUrl((root.screen?.name == "DP-1" ?? false) ? "5120x1728.png" : "1920x1296.png")
	property bool triedFallback: false;

	readonly property real remainingSize: image.sourceSize.height - root.height

	Image {
		id: image
		source: root.wallpaperPath
		y: -(root.slideAmount * root.remainingSize)
		fillMode: Image.PreserveAspectCrop

		onStatusChanged: {
			if (image.status === Image.Error && !root.triedFallback) {
				root.triedFallback = true;
				image.source = root.fallbackSource;
			}
		}
	}
}
