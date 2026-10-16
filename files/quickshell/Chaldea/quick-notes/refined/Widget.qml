// SPDX-License-Identifier: 0BSD
import QtQuick

NotesDrawer {
    property bool s0InnerFrame: true
    property int s1BodySize: 16
    property string s2NoteFont: "Share Tech Mono"
    property int s3GridStrength: 8

    doubleFrame: s0InnerFrame
    writingSize: s1BodySize
    writingFont: s2NoteFont === "Inter" ? sansFont : monoFont
    gridStrength: s3GridStrength
    property int editorHeight: 130
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
    redPalette: true
    allowDelete: true
    property string palette: "Original"
    property color backgroundColor: "#0a0a0a"
    property color textColor: "#e8e8e8"
    property color accentColor: "#cc1515"

    paletteName: palette
    customBackground: backgroundColor
    customText: textColor
    customAccent: accentColor
}
