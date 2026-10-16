// SPDX-License-Identifier: 0BSD
import QtQuick

NotesConsole {
    property string s0Spacing: "Compact"
    property string s1Heading: "Text"

    comfortable: s0Spacing === "Comfortable"
    redHeading: s1Heading === "Accent"
    property string palette: "Original"
    property int editorHeight: 119
    property int titleSize: 24
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
