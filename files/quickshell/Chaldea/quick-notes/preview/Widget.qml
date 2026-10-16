// SPDX-License-Identifier: 0BSD
import QtQuick

NotesPreview {
    property int s0Width: 414
    property bool s1Rule: true

    drawerWidth: s0Width
    headerMarker: s1Rule
    property string palette: "Original"
    property int editorHeight: 140
    property int titleSize: 18
    property string listDensity: "Comfortable"
    property int visibleNotes: 4
    property string newNotePosition: "Bottom"
    property string textCount: "Off"
    property bool showNumbers: true

    writingHeight: editorHeight
    headingSize: titleSize
    density: listDensity
    listRows: visibleNotes
    prependNewNotes: newNotePosition === "Top"
    counterMode: textCount
    numbered: showNumbers
    property color backgroundColor: "#111111"
    property color textColor: "#e8e8e8"
    property color accentColor: "#cc1515"

    paletteName: palette
    customBackground: backgroundColor
    customText: textColor
    customAccent: accentColor
}
