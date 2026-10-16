import QtQuick
import qs.Components
import qs.Settings

/*!
 * BuildStatus — live state of the running NixOS build.
 *
 * The widget streams `nixbuild-status --watch 1 --json --hide-idle`: the tool
 * prints one JSON line per state change and prints nothing at all while the
 * store is idle, so the capsule only takes bar space while something is
 * actually evaluating, building or activating. Detection happens inside the
 * tool (/proc + the Nix derivation log directory), never here: one poll costs
 * it ~4 ms and this process sleeps the rest of the time.
 */
WidgetCapsule {
    id: root

    // Last streamed state: idle | evaluating | building | activating.
    property string stateClass: "idle"
    property string statusText: ""
    property string statusTooltip: ""

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
    readonly property int labelMaxWidth: Math.round(280 * capsuleScale)

    forceHeightFromMetrics: true
    backgroundKey: "buildStatus"
    // Empty text is what the stream sends for idle: leave the row entirely
    // instead of holding an empty capsule.
    visible: root.statusText.length > 0

    implicitWidth: horizontalPadding * 2 + content.implicitWidth
    implicitHeight: forceHeightFromMetrics
        ? Math.max(uniformCapsuleHeight, content.implicitHeight + verticalPadding * 2)
        : content.implicitHeight + verticalPadding * 2

    Row {
        id: content
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
        targetItem: root
        text: root.statusTooltip
        visibleWhen: root.hovered
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
        }
        // A missing or killed tool must not leave a stale "building" capsule
        // behind; the restart policy brings the stream back on its own.
        onExited: (code, status) => {
            root.stateClass = "idle";
            root.statusText = "";
            root.statusTooltip = "";
        }
    }
}
