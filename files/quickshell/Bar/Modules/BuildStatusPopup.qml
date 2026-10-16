import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Settings
import "../../Helpers/Color.js" as Color

/*!
 * BuildStatusPopup — the separated list behind the bar's BuildStatus capsule:
 * one row per running build (command, target, derivation, elapsed), fed by the
 * `builds` array of `nixbuild-status --json`.
 */
PanelOverlaySurface {
    id: root

    property var builds: []
    // Capsule's on-screen x, so the popup opens aligned with the widget.
    property real triggerX: 0

    readonly property real _s: Theme.scale(screen) > 0 ? Theme.scale(screen) : 1.0

    backgroundColor: Color.withAlpha(Theme.surface, 0.92)
    borderColor: "transparent"
    borderWidth: 0
    width: Math.round(430 * _s)

    anchors {
        left: parent.left
        bottom: parent.bottom
        leftMargin: Math.max(4 * _s, root.triggerX)
        bottomMargin: Math.round(36 * _s)
    }

    // Same glyph/tone mapping as the capsule, so a row reads like the summary.
    function phaseIcon(phase) {
        if (phase === "building")
            return "build";
        if (phase === "activating")
            return "bolt";
        if (phase === "evaluating")
            return "search";
        return "check_circle";
    }
    function phaseColor(phase) {
        if (phase === "building")
            return Theme.accentPrimary;
        if (phase === "activating")
            return Theme.warning;
        return Theme.textSecondary;
    }
    // Second line of a row: what is compiling (single-session runs only) and
    // where the build was started.
    function detailLine(build) {
        var parts = [];
        if (build.drvs && build.drvs.length > 0)
            parts.push(String(build.drvs.join(", ")));
        if (build.cwd)
            parts.push(String(build.cwd).replace(/^\/home\/[^/]+/, "~"));
        if (build.target && build.head && build.head.indexOf(build.target) < 0)
            parts.push(String(build.target));
        return parts.join(" · ");
    }

    Column {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Math.round(14 * root._s)
        spacing: Math.round(10 * root._s)

        Text {
            text: root.builds.length === 1 ? "Nix build" : "Nix builds: " + root.builds.length
            color: Theme.textPrimary
            font.family: Theme.fontFamily
            font.pixelSize: Math.round(Theme.fontSizeBody * root._s)
            font.weight: Font.DemiBold
        }

        Text {
            visible: root.builds.length === 0
            text: "No builds running"
            color: Theme.textSecondary
            font.family: Theme.fontFamily
            font.pixelSize: Math.round(Theme.fontSizeSmall * root._s)
        }

        Repeater {
            model: root.builds
            delegate: Column {
                width: parent.width
                spacing: Math.round(3 * root._s)

                RowLayout {
                    width: parent.width
                    spacing: Math.round(8 * root._s)

                    MaterialIcon {
                        icon: root.phaseIcon(modelData.phase)
                        color: root.phaseColor(modelData.phase)
                        size: Math.round(Theme.fontSizeSmall * root._s)
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Text {
                        text: modelData.head || modelData.family || ""
                        color: Theme.textPrimary
                        font.family: Theme.fontFamily
                        font.pixelSize: Math.round(Theme.fontSizeSmall * root._s)
                        elide: Text.ElideMiddle
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Text {
                        text: modelData.elapsed_text || ""
                        color: root.phaseColor(modelData.phase)
                        font.family: Theme.fontFamily
                        font.pixelSize: Math.round(Theme.fontSizeSmall * root._s)
                        Layout.alignment: Qt.AlignVCenter
                    }
                }

                Text {
                    width: parent.width
                    visible: text.length > 0
                    text: root.detailLine(modelData)
                    color: Theme.textSecondary
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.round(Theme.fontSizeCaption * root._s)
                    elide: Text.ElideMiddle
                    leftPadding: Math.round(22 * root._s)
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.borderSubtle
                    visible: index < root.builds.length - 1
                }
            }
        }
    }
}
