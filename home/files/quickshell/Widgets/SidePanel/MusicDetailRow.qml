import QtQuick 2.15
import QtQuick.Layouts 1.15
import Quickshell
import qs.Components
import qs.Settings

RowLayout {
    id: detailRow
    Layout.fillWidth: true
    property var screen: null
    property string iconName: ""
    property color iconColor: Theme.textPrimary
    property real iconSizeMultiplier: 1.05
    property real iconSizeOverride: 0
    property int iconAlignment: Qt.AlignVCenter
    property real spacingFactor: Theme.sidePanelSpacingTight
    property color textColor: Theme.textPrimary
    property string textValue: ""
    property string textFontFamily: Theme.fontFamily
    property int textFontWeight: Font.DemiBold
    property int textWrapMode: Text.NoWrap
    property int textElide: Text.ElideRight
    property int textAlignment: Qt.AlignVCenter
    property int fontPixelSize: Theme.fontSizeSmall
    property int textFormat: Text.PlainText

    spacing: Math.round(spacingFactor * Theme.scale(screen))

    MaterialIcon {
        icon: detailRow.iconName
        visible: detailRow.iconName.length > 0
        color: detailRow.iconColor
        Layout.alignment: detailRow.iconAlignment
        size: detailRow.iconSizeOverride > 0
              ? Math.round(detailRow.iconSizeOverride)
              : Math.round(detailRow.fontPixelSize * detailRow.iconSizeMultiplier)
    }

    Text {
        id: label
        Layout.fillWidth: true
        text: detailRow.textValue
        textFormat: detailRow.textFormat
        color: detailRow.textColor
        font.family: detailRow.textFontFamily
        font.pixelSize: detailRow.fontPixelSize
        font.weight: detailRow.textFontWeight
        wrapMode: detailRow.textWrapMode
        elide: detailRow.textElide
        Layout.alignment: detailRow.textAlignment
    }
}
