// SPDX-License-Identifier: 0BSD
import QtQuick

NotesDrawer {
    property bool s0InnerFrame: true
    property int s1BodySize: 16
    property string s2Palette: "Bone"

    doubleFrame: s0InnerFrame
    writingSize: s1BodySize
    redPalette: s2Palette === "Red"
    property int editorHeight: 130
    property int titleSize: 17
    property string listDensity: "Comfortable"
    property int visibleNotes: 4
    property string newNotePosition: "Bottom"
    property string textCount: "Off"
    property bool showNumbers: false

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

    paletteName: s2Palette
    customBackground: backgroundColor
    customText: textColor
    customAccent: accentColor
}
