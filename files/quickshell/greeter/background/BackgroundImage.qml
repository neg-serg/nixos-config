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

	readonly property real remainingSize: Math.max(0, image.height - root.height)

	// Fallback when wallpaper is missing — black with a subtle dot grid
	Canvas {
		anchors.fill: parent
		visible: image.status === Image.Error || image.status === Image.Null

		onPaint: {
			const ctx = getContext("2d");
			const w = width;
			const h = height;

			// Solid near-black base
			ctx.fillStyle = "#0a0a0c";
			ctx.fillRect(0, 0, w, h);

			// Subtle dot grid
			const spacing = 48;
			const dotRadius = 1.5;
			ctx.fillStyle = "#1a1a20";

			for (let x = spacing / 2; x < w; x += spacing) {
				for (let y = spacing / 2; y < h; y += spacing) {
					ctx.beginPath();
					ctx.arc(x, y, dotRadius, 0, Math.PI * 2);
					ctx.fill();
				}
			}
		}
	}

	Image {
		id: image
		asynchronous: root.asynchronous
		source: root.wallpaperPath

		// Cover the full screen while preserving aspect ratio,
		// matching swayimg's default scale behaviour.
		// The image is sized so it always fills both axes — what
		// doesn't fit is cropped (PreserveAspectCrop).
		width: root.width
		height: Math.max(root.height, root.width * (sourceSize.height / Math.max(sourceSize.width, 1)))
		fillMode: Image.PreserveAspectCrop

		// Slide up when the password field is focused to reveal
		// more of the image bottom.
		y: -(root.slideAmount * root.remainingSize)
	}
}
