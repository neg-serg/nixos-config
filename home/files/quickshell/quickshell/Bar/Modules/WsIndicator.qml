import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Components
import qs.Services as Services
import qs.Settings
import "../../Helpers/RichText.js" as Rich
import "../../Helpers/WsIconMap.js" as WsMap
import "../../Helpers/WorkspaceIcons.js" as WorkspaceIcons
CenteredCapsuleRow {
    id: root
    property string wsName: "?"
    property int wsId: -1
    property string submapName: ""
    property var submapDynamicMap: ({})
    property bool showWorkspaceGlyph: true
    property bool showLabel: true
    property bool showSubmapIcon: true
    property bool workspaceGlyphDetached: false
    property var workspaceIconEntry: WorkspaceIcons.entryForWorkspace(root.wsName, root.wsId)
    property bool workspaceIconValid: workspaceIconEntry && workspaceIconEntry.path && workspaceIconEntry.path.length > 0
    property string workspaceIconPathData: workspaceIconValid ? workspaceIconEntry.path : ""
    property int workspaceIconViewBox: WorkspaceIcons.manifestViewBox()
    // Map submap name to icon via helper + overrides + dynamic mapping
    function submapIconName(name) {
        const key = (name || "").toLowerCase().trim();
        if (submapDynamicMap && submapDynamicMap[key]) return submapDynamicMap[key];
        return WsMap.submapIcon(key, Theme.wsSubmapIconOverrides);
    }

    property color workspaceGlyphColor: Theme.accentHover
    property color gothicColor: Theme.textPrimary

    backgroundKey: "workspaces"

    // RichText helpers are provided by Helpers/RichText.js

    function isPUA(cp) { return cp >= 0xE000 && cp <= 0xF8FF; }          // Private Use Area (icon fonts)
    function isOldItalic(cp){ return cp >= 0x10300 && cp <= 0x1034F; }
    // Wrap one char into colored span by category
    function spanForChar(ch) {
        const cp = ch.codePointAt(0);
        if (isPUA(cp)) { return Rich.colorSpan(workspaceGlyphColor, ch); }
        if (isOldItalic(cp)) { return Rich.colorSpan(gothicColor, ch); }
        if (ch === "·") return " ";
        return Rich.esc(ch);
    }

    // Decorate string with category spans
    function decorateName(name) {
        if (!name || typeof name !== "string") return Rich.esc(name || "");
        let out = "";
        for (let i = 0; i < name.length; ) {
            const cp = name.codePointAt(i);
            const ch = String.fromCodePoint(cp);
            out += spanForChar(ch);
            i += (cp > 0xFFFF) ? 2 : 1; // handle surrogate pairs
        }
        return out;
    }

    // Split leading PUA icon
    function leadingIcon(name) {
        if (!name || typeof name !== "string" || name.length === 0) return "";
        const cp = name.codePointAt(0);
        return isPUA(cp) ? String.fromCodePoint(cp) : "";
    }

    function restAfterLeadingIcon(name) {
        if (!name || typeof name !== "string" || name.length === 0) return "";
        const cp = name.codePointAt(0);
        if (!isPUA(cp)) return name;
        const skip = (cp > 0xFFFF) ? 2 : 1;
        // Trim immediate whitespace after icon
        return name.substring(skip).replace(/^\s+/, "");
    }


    // Final values for display
    property string iconGlyph: leadingIcon(wsName)
    property string restName: restAfterLeadingIcon(wsName)

    // Detect terminal workspace
    readonly property var _terminalIcons: ["\uf120", "\ue795", "\ue7a2"]
    property bool isTerminalWs: (function(){
        const rn = (restName || "").toLowerCase().trim();
        if (iconGlyph && _terminalIcons.indexOf(iconGlyph) !== -1) return true;
        if (rn.startsWith("term")) return true;
        if (rn.endsWith("term")) return true; // e.g., names like "dev-term"
        return false;
    })()

    // Fallback to workspace id if name is empty
    property string fallbackText: (wsId >= 0 ? String(wsId) : "?")

    // RichText decoration
    property string decoratedText: (restName && restName.length > 0)
                                   ? decorateName(restName)
                                   : decorateName(fallbackText)

    iconVisible: root.showSubmapIcon && (!root.workspaceGlyphDetached) && root.submapName && root.submapName.length > 0
    iconMode: "material"
    materialIconName: submapIconName(root.submapName)
    iconColor: Theme.wsSubmapIconColor
    iconAutoTune: true
    iconPadding: Theme.wsIconInnerPadding
    iconSpacing: Math.max(0, Theme.wsIconSpacing)
    labelIsRichText: true
    labelVisible: root.showLabel
    labelText: decoratedText
    fontPixelSize: Math.round(Theme.fontSizeSmall * root.capsuleScale)
    labelFontFamily: Theme.fontFamily
    labelFontWeight: Font.Medium
    labelColor: Theme.textPrimary
    textPadding: Math.max(0, Theme.wsLabelPadding)
    labelLeftPaddingOverride: root.isTerminalWs ? Theme.wsLabelLeftPaddingTerminal : Theme.wsLabelLeftPadding

    leadingContent: Item {
        readonly property bool glyphPresent: root.showWorkspaceGlyph && (root.workspaceIconValid || iconGlyph.length > 0)
        readonly property real glyphWidth: Math.max(
            (workspaceSvgIcon.visible && workspaceSvgIcon.implicitWidth > 0) ? workspaceSvgIcon.implicitWidth : 0,
            (workspaceTextIcon.visible && workspaceTextIcon.implicitWidth > 0) ? workspaceTextIcon.implicitWidth : 0
        )
        width: glyphPresent ? glyphWidth : 0
        height: root.desiredInnerHeight

        BaselineAlignedIcon {
            id: workspaceSvgIcon
            anchors.centerIn: parent
            visible: root.workspaceIconValid
            mode: "svg"
            alignMode: "optical"
            svgPathData: root.workspaceIconPathData
            svgViewBox: root.workspaceIconViewBox
            color: workspaceGlyphColor
            padding: root.workspaceGlyphDetached ? Theme.wsIconDetachedPadding : Theme.wsIconInnerPadding
            autoTune: !root.workspaceGlyphDetached
            labelRef: root.workspaceGlyphDetached ? null : root.labelItem
            alignTarget: root.workspaceGlyphDetached ? null : root.labelItem
            scaleToken: root.workspaceGlyphDetached ? (Theme.wsIconScale * Theme.wsIconDetachedScale) : Theme.wsIconScale
            baselineOffsetToken: root.workspaceGlyphDetached
                ? (Theme.wsIconBaselineOffset + Theme.wsIconDetachedBaselineOffset)
                : Theme.wsIconBaselineOffset
        }

        BaselineAlignedIcon {
            id: workspaceTextIcon
            anchors.centerIn: parent
            visible: !root.workspaceIconValid && iconGlyph.length > 0
            mode: "text"
            alignMode: "optical"
            text: iconGlyph
            color: workspaceGlyphColor
            fontFamily: Theme.fontFamily
            padding: root.workspaceGlyphDetached ? Theme.wsIconDetachedPadding : Theme.wsIconInnerPadding
            autoTune: !root.workspaceGlyphDetached
            labelRef: root.workspaceGlyphDetached ? null : root.labelItem
            scaleToken: root.workspaceGlyphDetached ? (Theme.wsIconScale * Theme.wsIconDetachedScale) : undefined
            baselineOffsetToken: root.workspaceGlyphDetached
                ? (Theme.wsIconBaselineOffset + Theme.wsIconDetachedBaselineOffset)
                : undefined
        }
    }

    function updateDynamicMap(binds) {
        try {
            const dyn = {};
            const list = Array.isArray(binds) ? binds : [];
            for (let i = 0; i < list.length; i++) {
                const sub = (list[i] && list[i].submap) ? String(list[i].submap) : "";
                const n = sub.toLowerCase().trim();
                if (!n || n === "default" || n === "reset") continue;
                dyn[n] = submapIconName(n);
            }
            submapDynamicMap = dyn;
            try { const _ = Object.keys(dyn); } catch (_) {}
        } catch (e) {}
    }

    Connections {
        target: Services.HyprlandWatcher
        function onActiveWorkspaceIdChanged() {
            const id = Services.HyprlandWatcher.activeWorkspaceId;
            if (typeof id === "number") root.wsId = id;
        }
        function onActiveWorkspaceNameChanged() {
            root.wsName = Services.HyprlandWatcher.activeWorkspaceName || "";
        }
        function onCurrentSubmapChanged() { root.submapName = Services.HyprlandWatcher.currentSubmap || ""; }
        function onFocusedMonitorEvent() { Services.HyprlandWatcher.refreshWorkspace(); }
        function onBindsChanged() { updateDynamicMap(Services.HyprlandWatcher.binds); }
    }

    Component.onCompleted: {
        root.wsId = Services.HyprlandWatcher.activeWorkspaceId;
        root.wsName = Services.HyprlandWatcher.activeWorkspaceName;
        root.submapName = Services.HyprlandWatcher.currentSubmap;
        updateDynamicMap(Services.HyprlandWatcher.binds);
        Services.HyprlandWatcher.refreshWorkspace();
        Services.HyprlandWatcher.refreshBinds();
    }

}
