import QtQuick
import qs.Components
import qs.Settings

/*!
 * BuildStatus — bar capsule for running Nix builds.
 *
 * Streams `nixbuild-status --watch 1 --json --hide-idle`: the tool prints one
 * JSON line per state change and nothing at all while the store is idle, so
 * the capsule only takes bar space while something is actually evaluating,
 * building or activating. The capsule carries the summary (count + what is
 * compiling now); the tooltip and the tap-through popup list every build
 * separately. Detection happens inside the tool (/proc + the Nix derivation
 * log directory), never here.
 */
OverlayToggleCapsule {
    id: root

    // Last streamed state: idle | evaluating | building | activating.
    property string stateClass: "idle"
    property string statusText: ""
    property string statusTooltip: ""
    // Sessions, as streamed in the JSON `builds` array (one entry per build).
    property var builds: []
    // On-screen x of the capsule; the popup opens aligned with it.
    property real triggerX: 0

    readonly property real capsuleScale: capsule.capsuleScale
    // Material Symbols names, the same icon set the neighbouring capsules use.
    readonly property string stateIcon: {
        if (root.stateClass === "building")
            return "build";
        if (root.stateClass === "activating")
            return "bolt";
        if (root.stateClass === "evaluating")
            return "search";
        return "check_circle";
    }
    readonly property color stateColor: {
        if (root.stateClass === "building")
            return Theme.accentPrimary;
        if (root.stateClass === "activating")
            return Theme.warning;
        return Theme.textSecondary;
    }
    // Derivation names can be long; cap the label and elide the middle so the
    // version suffix stays readable.
    readonly property int labelMaxWidth: Math.round(280 * root.capsuleScale)

    // Empty text is what the stream sends for idle: leave the row entirely
    // instead of holding an empty capsule.
    capsuleVisible: root.statusText.length > 0
    autoToggleOnTap: true
    overlayNamespace: "qs-buildstatus"
    capsule.backgroundKey: "buildStatus"
    capsule.centerContent: true
    capsule.implicitWidth: capsule.horizontalPadding * 2 + contentRow.implicitWidth

    Row {
        id: contentRow
        anchors.centerIn: parent
        spacing: Math.round(Theme.panelRowSpacingSmall * root.capsuleScale)

        MaterialIcon {
            id: stateGlyph
            icon: root.stateIcon
            color: root.stateColor
            size: Math.round(Theme.fontSizeSmall * root.capsuleScale)
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            id: statusLabel
            text: root.statusText
            color: root.stateColor
            font.family: Theme.fontFamily
            font.pixelSize: Math.round(Theme.fontSizeSmall * root.capsuleScale)
            width: Math.min(implicitWidth, root.labelMaxWidth)
            elide: Text.ElideMiddle
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    PanelTooltip {
        targetItem: root.capsule
        text: root.statusTooltip
        visibleWhen: root.capsule.hovered
    }

    overlayChildren: [
        BuildStatusPopup {
            screen: root.screen
            builds: root.builds
            triggerX: root.triggerX
        }
    ]

    // Resolve the capsule's global x once laid out (Qt.callLater defers past
    // the initial (0,0) layout position).
    Component.onCompleted: {
        Qt.callLater(function () {
            root.triggerX = root.capsule.mapToGlobal(0, 0).x;
        });
    }

    // Long-lived stream: the tool emits a line only when its rendered state
    // changes, so this costs one sleeping process per screen and no polling.
    ProcessRunner {
        id: statusStream
        cmd: [
            "nixbuild-status",
            "--watch", "1",
            "--json",
            "--icons", "none",
            "--compact",
            "--hide-idle"
        ]
        jsonLine: true
        restartMode: "always"
        backoffMs: 2000

        onJson: obj => {
            root.stateClass = String(obj["class"] || "idle");
            root.statusText = String(obj.text || "");
            root.statusTooltip = String(obj.tooltip || "");
            root.builds = obj.builds || [];
        }
        // A missing or killed tool must not leave a stale "building" capsule
        // behind; the restart policy brings the stream back on its own.
        onExited: (code, status) => {
            root.stateClass = "idle";
            root.statusText = "";
            root.statusTooltip = "";
            root.builds = [];
        }
    }
}
