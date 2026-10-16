// SPDX-License-Identifier: 0BSD
import QtQuick

NotesStack {
    property bool s0Grid: true

    showGrid: s0Grid
    property string palette: "Original"
    property int editorHeight: 122
    property int titleSize: 16
    property string listDensity: "Comfortable"
    property int visibleNotes: 4
    property string newNotePosition: "Top"
    property string textCount: "Off"
    property bool showNumbers: true

    writingHeight: editorHeight
    headingSize: titleSize
    density: listDensity
    listRows: visibleNotes
    prependNewNotes: newNotePosition === "Top"
    counterMode: textCount
    numbered: showNumbers
    property color backgroundColor: "#c8c8c4"
    property color textColor: "#2e2a1f"
    property color accentColor: "#cc1515"

    paletteName: palette
    customBackground: backgroundColor
    customText: textColor
    customAccent: accentColor
}
