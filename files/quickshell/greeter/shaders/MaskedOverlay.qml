pragma ComponentBehavior: Bound
import QtQuick

ShaderEffect {
	id: root
	property Item overlayItem;
	property point overlayPos: Qt.point(root.overlayItem.x, root.overlayItem.y);

	fragmentShader: Qt.resolvedUrl("masked_overlay.frag.qsb")

	property point pOverlayPos: Qt.point(
		root.overlayPos.x / root.width,
		root.overlayPos.y / root.height
	);

	property point pOverlaySize: Qt.point(
		root.overlayItem.width / root.width,
		root.overlayItem.height / root.height
	);

	property point pMergeInset: Qt.point(
		3 / root.width,
		3 / root.height
	);

	property real pMergeCutoff: 0.15
}
