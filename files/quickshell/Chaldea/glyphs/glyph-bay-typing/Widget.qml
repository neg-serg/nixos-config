// SPDX-License-Identifier: 0BSD
import QtQuick

GlyphWidget {
    designName: "Glyph Bay typing"
    property int travel: 100
    property bool motion: true
    transitionTime: travel
    animationEnabled: motion
    glyphBay: true
}
