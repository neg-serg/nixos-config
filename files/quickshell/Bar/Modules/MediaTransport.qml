import QtQuick
import QtQuick.Layouts
import qs.Settings
import qs.Components
import qs.Services
import "../../Helpers/Color.js" as Color

// Playback controls for the media widget: they ride out to the LEFT of the
// media capsule while the cursor is on its cover art (or on the strip itself)
// and collapse again when the cursor leaves. The host wraps this in a
// SlideReveal, so the neighbouring widgets slide aside while it appears —
// the same behaviour the pill capsule has on the left side of the bar.
//
// Hover cannot be observed here: the panel-level tracker in Bar.qml
// (z: 10000) is the topmost hover-enabled item, so both the drive signal
// (sourceHovered) and the cursor position (pointerPos) are handed in by the
// host and tested against this widget's own geometry.
WidgetCapsule {
    id: root

    forceHeightFromMetrics: true
    backgroundKey: "media"
    paddingScale: 1.5
    // Square cover art in the bar means no vertical padding here either.
    verticalPaddingScale: 0
    verticalPaddingMin: 0

    // Cursor is over the media widget's cover art.
    property bool sourceHovered: false
    // Cursor position in this widget's coordinates, and whether it is current
    // (the tracker keeps its last position after the cursor leaves the bar, so
    // the position alone must never keep the strip open).
    property point pointerPos: Qt.point(-1, -1)
    property bool pointerActive: false

    readonly property bool pointerInside: pointerActive && pointerPos.x >= 0 && pointerPos.y >= 0
        && pointerPos.x <= width && pointerPos.y <= height

    // Open while either hover is active, plus a short grace period so that
    // moving between the cover and the buttons does not flicker the strip.
    readonly property bool wantExpanded: (sourceHovered || pointerInside) && MusicManager.hasPlayer
    property bool expanded: false

    Timer {
        id: closeGrace
        // Long enough not to fire while the cursor is only passing over the
        // cover; the collapse itself is animated (see the host's SlideReveal).
        interval: 300
        repeat: false
        onTriggered: if (!root.wantExpanded) root.expanded = false
    }
    onWantExpandedChanged: {
        if (wantExpanded) {
            closeGrace.stop();
            expanded = true;
        } else {
            closeGrace.restart();
        }
    }
    Component.onCompleted: if (wantExpanded) expanded = true

    implicitWidth: Math.max(capsuleInner, buttonRow.implicitWidth + horizontalPadding * 2)

    RowLayout {
        id: buttonRow
        anchors.centerIn: parent
        spacing: Math.round(6 * root.capsuleScale)

        TransportButton {
            glyph: "skip_previous"
            enabled: MusicManager.canGoPrevious
            onActivated: MusicManager.previous()
        }
        TransportButton {
            glyph: MusicManager.isPlaying ? "pause" : "play_arrow"
            enabled: MusicManager.canPlay || MusicManager.canPause
            onActivated: MusicManager.playPause()
        }
        TransportButton {
            glyph: "skip_next"
            enabled: MusicManager.canGoNext
            onActivated: MusicManager.next()
        }
    }

    // Icon-only button sized from the bar's media text size so the strip
    // scales with the panel. Hover feedback comes from pointerPos (see the
    // file header) instead of MouseArea.containsMouse, which never becomes
    // true under the panel tracker.
    component TransportButton: Item {
        id: transportButton

        property string glyph: ""
        signal activated()

        readonly property int glyphPx: Math.max(12, Math.round(Theme.fontSizeSmall * root.capsuleScale * 1.1))
        readonly property bool pointerOver: (function() {
            if (root.pointerPos.x < 0 || root.pointerPos.y < 0) return false;
            var origin = transportButton.mapToItem(root, 0, 0);
            return root.pointerPos.x >= origin.x && root.pointerPos.x <= origin.x + width
                && root.pointerPos.y >= origin.y && root.pointerPos.y <= origin.y + height;
        })()

        implicitWidth: Math.round(glyphPx * 1.6)
        implicitHeight: Math.round(glyphPx * 1.6)

        MaterialIcon {
            anchors.centerIn: parent
            icon: transportButton.glyph
            size: transportButton.glyphPx
            color: !transportButton.enabled
                ? Color.withAlpha(Theme.textPrimary, 0.35)
                : (transportButton.pointerOver ? MusicManager.accentColor : Theme.textPrimary)
            Behavior on color { ColorAnimation { duration: 150 } }
        }

        MouseArea {
            anchors.fill: parent
            enabled: transportButton.enabled
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: transportButton.activated()
        }
    }
}
