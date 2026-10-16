// SPDX-License-Identifier: 0BSD
import QtQuick

NotesIndex {
    property int s0IndexWidth: 150
    property int s1RowHeight: 58

    indexWidth: s0IndexWidth
    defaultRowHeight: s1RowHeight
    property string palette: "Original"
    property int editorHeight: 214
    property int titleSize: 16
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
    property color backgroundColor: "#0a0a0a"
    property color textColor: "#e8e8e8"
    property color accentColor: "#cc1515"

    paletteName: palette
    customBackground: backgroundColor
    customText: textColor
    customAccent: accentColor
}
