import QtQuick 2.15
import QtQuick.Layouts 1.15
import qs.Components
import qs.Settings

RowLayout {
    id: detailRow
    Layout.fillWidth: true
    property var screen: null
    property string iconName: ""
    property color iconColor: Theme.textPrimary
    property real iconSizeMultiplier: 1.05
    property int iconAlignment: Qt.AlignVCenter
    property color textColor: Theme.textPrimary
    property string textValue: ""
    property int textAlignment: Qt.AlignVCenter
    property int fontPixelSize: Theme.fontSizeSmall
    property int textFormat: Text.PlainText

    spacing: Math.round(Theme.sidePanelSpacingTight * Theme.scale(screen))

    MaterialIcon {
        icon: detailRow.iconName
        visible: detailRow.iconName.length > 0
        color: detailRow.iconColor
        Layout.alignment: detailRow.iconAlignment
        size: Math.round(detailRow.fontPixelSize * detailRow.iconSizeMultiplier)
    }

    Text {
        id: label
        Layout.fillWidth: true
        text: detailRow.textValue
        textFormat: detailRow.textFormat
        color: detailRow.textColor
        font.family: Theme.fontFamily
        font.pixelSize: detailRow.fontPixelSize
        font.weight: Font.DemiBold
        wrapMode: Text.NoWrap
        elide: Text.ElideRight
        Layout.alignment: detailRow.textAlignment
    }
}
