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

	readonly property real remainingSize: image.height - root.height

	Rectangle {
		anchors.fill: parent
		visible: image.status === Image.Error || image.status === Image.Null
		gradient: Gradient {
			GradientStop { position: 0.0; color: "#101010" }
			GradientStop { position: 1.0; color: "#000000" }
		}
	}

	Image {
		id: image
		width: root.width
		height: root.width * (image.sourceSize.height / Math.max(image.sourceSize.width, 1))
		source: root.wallpaperPath
		y: -(root.slideAmount * root.remainingSize)
	}
}
