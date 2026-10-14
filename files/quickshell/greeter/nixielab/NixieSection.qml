import QtQuick
import QtQuick.Layouts

// A titled group of the nixie menu: the heading, a hairline, and the widgets
// the caller declares as children (declared after the two internal items, so
// they land below the rule). Children are laid out by this ColumnLayout.
ColumnLayout {
    id: section

    property string title: ""

    Layout.fillWidth: true
    spacing: 6

    Text {
        Layout.fillWidth: true
        text: section.title
        color: "#e8eaf0"
        font.pixelSize: 14
        font.weight: Font.DemiBold
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: "#2c313b"
    }
}
