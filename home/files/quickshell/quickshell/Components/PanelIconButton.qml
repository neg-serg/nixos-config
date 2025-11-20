import QtQuick
import qs.Settings
import "." as LocalComponents

/*!
 * PanelIconButton presets IconButton styling to match panel expectations.
 * Consumers typically only override icon, size, and event handlers.
 */
LocalComponents.IconButton {
    id: root

    property bool useAccentBorder: true

    cornerRadius: Theme.cornerRadiusSmall
    accentColor: useAccentBorder ? Theme.accentPrimary : "transparent"
    iconNormalColor: Theme.textPrimary
    iconHoverColor: Theme.onAccent
    cursorShape: Qt.PointingHandCursor
}
