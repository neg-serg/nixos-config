import QtQuick
import qs.Settings
import "." as LocalComponents

/*!
 * PanelTooltip applies shared defaults for tooltips used across the panel.
 * Consumers bind `visibleWhen` to any condition; the component manages the
 * underlying StyledTooltip.
 */
LocalComponents.StyledTooltip {
    id: root

    property bool visibleWhen: false
    delay: Theme.tooltipDelayMs
    tooltipVisible: visibleWhen
}
