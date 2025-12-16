import QtQuick
import qs.Components
import "../../Helpers/TooltipText.js" as TooltipText

AudioEndpointCapsule {
    id: root

    property string tooltipTitle: ""
    property string tooltipValueText: ""
    property var tooltipHints: []
    property bool enableAdvancedToggle: false
    property Item advancedSelector: defaultSelector

    readonly property string _computedValue: (function() {
        if (tooltipValueText && tooltipValueText.length) return tooltipValueText;
        var lvl = (root.level !== undefined && root.level !== null) ? root.level : 0;
        return lvl + "%";
    })()
    readonly property string _tooltipText: TooltipText.compose(tooltipTitle, _computedValue, tooltipHints)

    Item {
        id: defaultSelector
        visible: false
        function show() { visible = true }
        function dismiss() { visible = false }
    }

    PanelTooltip {
        id: tooltip
        text: root._tooltipText
        targetItem: root.pill
        visibleWhen: root.containsMouse && !(root.enableAdvancedToggle && root.advancedSelector && root.advancedSelector.visible)
    }

    onClicked: {
        if (!root.enableAdvancedToggle) return;
        if (!root.advancedSelector) return;
        root.advancedSelector.visible = !root.advancedSelector.visible;
    }
}
