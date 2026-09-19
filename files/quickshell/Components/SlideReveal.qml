// SlideReveal: animates the horizontal reveal/collapse of an inline item
// inside a Qt Quick layout (RowLayout/Row). The child content is clipped and
// the item's Layout.preferredWidth animates between 0 and the content width,
// so neighbours slide aside smoothly while the content "rides out".
//
// Usage inside a RowLayout (the component contributes only Layout.* sizing,
// so set Layout.alignment yourself, e.g. Qt.AlignVCenter):
//
//   SlideReveal {
//       revealed: myCondition
//       Layout.alignment: Qt.AlignVCenter
//       MyCapsule { ... }
//   }
//
// The open width/height are auto-detected from the single content item; pass
// contentWidthHint/contentHeightHint to override when the content sizes
// itself dynamically. Respects Theme.animationsEnabled (reduced motion).
import QtQuick
import QtQuick.Layouts
import qs.Settings

Item {
    id: root
    clip: true

    // The child to reveal (a single visual item).
    default property alias content: revealContent.data

    // Show (true) or collapse (false) the contained item.
    property bool revealed: false
    // When false the state switches instantly (reduced-motion friendly).
    property bool animate: Theme.animationsEnabled
    // Slide duration. Opening and closing are timed separately: collapsing an
    // item away is read as abrupt when it snaps back at the open speed, so the
    // close is normally given more time (and a smoother curve) than the open.
    property int durationMs: Theme.panelAnimStdMs
    property int openDurationMs: root.durationMs
    property int closeDurationMs: root.durationMs
    // Easing curve used while opening/closing.
    property int easing: Theme.uiEasingStdOut
    property int openEasing: root.easing
    property int closeEasing: root.easing
    // Optional open-size overrides; auto-detected when left at -1.
    property real contentWidthHint: -1
    property real contentHeightHint: -1

    readonly property Item contentItem: revealContent.children.length > 0
        ? revealContent.children[revealContent.children.length - 1] : null
    readonly property real openWidth: root.contentWidthHint >= 0
        ? root.contentWidthHint
        : (root.contentItem ? root.contentItem.width : 0)
    readonly property real openHeight: root.contentHeightHint >= 0
        ? root.contentHeightHint
        : (root.contentItem ? root.contentItem.height : 0)

    // 0 = collapsed, 1 = fully revealed. Animating this single value drives
    // both the width and the content fade, so the two can never drift apart,
    // and the timing/curve can be picked per direction (see above).
    property real progress: root.revealed ? 1 : 0

    Behavior on progress {
        enabled: root.animate
        NumberAnimation {
            duration: root.revealed ? root.openDurationMs : root.closeDurationMs
            easing.type: root.revealed ? root.openEasing : root.closeEasing
        }
    }

    Layout.preferredWidth: root.openWidth * root.progress
    Layout.preferredHeight: Math.max(1, root.openHeight)
    implicitWidth: 0
    implicitHeight: Math.max(1, root.openHeight)

    // Inner content fades in/out while it slides.
    Item {
        id: revealContent
        opacity: root.progress
    }
}
