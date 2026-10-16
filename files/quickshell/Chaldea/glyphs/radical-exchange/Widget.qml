// SPDX-License-Identifier: 0BSD
import QtQuick

GlyphWidget {
    designName: "Radical exchange"
    property int duration: 220
    property int red: 100
    property bool motion: true
    transitionTime: duration
    emphasis: red
    animationEnabled: motion
}
