import QtQuick
import QtQuick.Effects
import qs.Settings
import "../Helpers/Utils.js" as Utils
import "../Helpers/Format.js" as Format

Item {
    id: revealPill

    // External properties
    property string icon: ""
    property string text: ""
    property color pillColor: Theme.panelPillColor
    property color textColor: Theme.textPrimary
    property color iconCircleColor: Theme.accentPrimary
    property color iconTextColor: Theme.background
    property color collapsedIconColor: Theme.textPrimary
    // When true (default) the icon sits on a solid level-coloured disc behind
    // it; set to false to render the plain icon with no circle.
    property bool showDisc: true
    // Optional path to a custom SVG icon. When set it replaces the Material
    // glyph and is recoloured to the icon colour via MultiEffect.colorization.
    property string iconSource: ""
    // Colour the icon is painted with. Without a disc it is always the level
    // colour (collapsedIconColor) so the volume tint is always visible.
    readonly property color _iconColor: showDisc ? (showPill ? iconTextColor : collapsedIconColor) : collapsedIconColor
    // Unit colouring: paint the unit suffix (e.g. "dB") and a leading sign
    // ("-") with accentUnitColor while the digits keep textColor. Enabled by
    // the audio readout that wants the wallpaper accent on "dB"/minus.
    property bool colorizeUnit: false
    property color accentUnitColor: Theme.accentPrimary
    property int pillHeight: Math.round(Theme.panelPillHeight * Theme.scale(Screen))
    property int iconSize: Math.round(Theme.panelPillIconSize * Theme.scale(Screen))
    property int pillPaddingHorizontal: Theme.panelPillPaddingH
    property bool autoHide: false
    property int pillCornerRadius: Math.max(0, Math.round(Theme.cornerRadiusSmall * Theme.scale(Screen)))
    // Optional override for how long the pill stays visible before auto-hiding
    property int autoHidePauseMs: Theme.panelPillAutoHidePauseMs
    // Optional override for how long to wait before showing the pill
    property int showDelayMs: Theme.panelPillShowDelayMs

    // Internal state
    property bool showPill: false
    property bool shouldAnimateHide: false

    // Split the label into digit runs (kept in textColor) and non-digit runs
    // (unit/sign, e.g. "-dB") coloured with accentUnitColor. Returns an HTML
    // rich-text string; plain when there is nothing to colour.
    readonly property string _unitRichText: (function() {
        const s = revealPill.text;
        if (!s) return "";
        let out = "";
        let i = 0;
        const isDigit = ch => ch >= "0" && ch <= "9";
        while (i < s.length) {
            const d = isDigit(s[i]);
            let j = i;
            while (j < s.length && isDigit(s[j]) === d) j++;
            const seg = s.slice(i, j);
            const col = d ? textColor : accentUnitColor;
            out += '<span style="color:' + Format.colorCss(col) + '">' + seg + "</span>";
            i = j;
        }
        return out;
    })()

    // Exposed width logic
    readonly property int pillOverlap: iconSize / 2
    readonly property int maxPillWidth: Utils.clamp(textItem.implicitWidth + pillPaddingHorizontal * 2 + pillOverlap, 1, textItem.implicitWidth + pillPaddingHorizontal * 2 + pillOverlap)


    width: iconSize + (showPill ? maxPillWidth - pillOverlap : 0)
    height: pillHeight

    Rectangle {
        id: pill
        width: showPill ? maxPillWidth : 1
        height: pillHeight
        x: (iconCircle.x + iconCircle.width / 2) - width
        opacity: showPill ? 1 : 0
        color: pillColor
        topLeftRadius: pillCornerRadius
        bottomLeftRadius: pillCornerRadius
        anchors.verticalCenter: parent.verticalCenter

        Text {
            id: textItem
            anchors.centerIn: parent
            text: revealPill.colorizeUnit ? revealPill._unitRichText : revealPill.text
            textFormat: revealPill.colorizeUnit ? Text.RichText : Text.PlainText
            font.pixelSize: Theme.fontSizeSmall * Theme.scale(Screen)
            font.family: Theme.fontFamily
            font.weight: Font.Bold
            color: textColor
            visible: showPill
        }

        Behavior on width { enabled: showAnim.running || hideAnim.running; NumberStdOutBehavior {} }
        Behavior on opacity { enabled: showAnim.running || hideAnim.running; NumberStdOutBehavior {} }
    }

    Rectangle {
        id: iconCircle
        width: iconSize
        height: iconSize
        radius: width / 2
        color: showPill && showDisc ? iconCircleColor : "transparent"
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right

        Behavior on color { enabled: Theme.animationsEnabled; ColorFastInOutBehavior {} }

        // Custom SVG icon (e.g. Genelec "The Ones"): recoloured to the icon
        // colour. When none is set we keep the Material glyph so the component
        // stays generic for volume/microphone.
        Image {
            id: iconImage
            anchors.centerIn: parent
            width: iconSize
            height: iconSize
            source: revealPill.iconSource
            sourceSize: Qt.size(Math.round(iconSize * 2), Math.round(iconSize * 2))
            fillMode: Image.PreserveAspectFit
            smooth: true
            asynchronous: true
            visible: revealPill.iconSource.length > 0
            layer.enabled: true
            layer.effect: MultiEffect {
                // Recolour the monochrome SVG to the current icon colour.
                saturation: 0
                colorization: 1.0
                colorizationColor: revealPill._iconColor
            }
        }

        MaterialIcon {
            id: iconGlyph
            anchors.centerIn: parent
            rounded: showPill
            size: Theme.fontSizeSmall * Theme.scale(Screen)
            icon: revealPill.icon
            // No disc: the icon is always painted with the level colour so the
            // volume tint shows at all times.
            color: revealPill._iconColor
            visible: revealPill.iconSource.length === 0
        }
    }

    ParallelAnimation {
        id: showAnim
        running: false
        NumberStdOutBehavior { target: pill; property: "width";   from: 1;            to: maxPillWidth }
        NumberStdOutBehavior { target: pill; property: "opacity"; from: 0;            to: 1 }
        onStarted: {
            showPill = true;
        }
        onStopped: {
            delayedHideAnim.start();

        }
    }

    SequentialAnimation {
        id: delayedHideAnim
        running: false
        PauseAnimation { duration: autoHidePauseMs }
        ScriptAction {
            script: if (shouldAnimateHide)
                hideAnim.start()
        }
    }

    ParallelAnimation {
        id: hideAnim
        running: false
        NumberStdInBehavior { target: pill; property: "width";   from: maxPillWidth; to: 1 }
        NumberStdInBehavior { target: pill; property: "opacity"; from: 1;            to: 0 }
        onStopped: {
            showPill = false;
            shouldAnimateHide = false;

        }
    }

    function show() {
        if (!Theme.animationsEnabled) {
            showPill = true;
            shouldAnimateHide = autoHide;
            showTimer.stop();
            delayedHideAnim.stop();
            hideAnim.stop();

            return;
        }
        if (!showPill) {
            shouldAnimateHide = autoHide;
            showAnim.start();
        } else {
            hideAnim.stop();
            delayedHideAnim.restart();
        }
    }

    function hide() {
        if (!Theme.animationsEnabled) {
            if (showPill) {
                showPill = false;
                shouldAnimateHide = false;
    
            }
            showTimer.stop();
            delayedHideAnim.stop();
            hideAnim.stop();
            return;
        }
        if (showPill) {
            hideAnim.start();
        }
        showTimer.stop();
    }

    function showDelayed() {
        if (!Theme.animationsEnabled) {
            show();
            return;
        }
        if (!showPill) {
            shouldAnimateHide = autoHide;
            showTimer.start();
        } else {
            hideAnim.stop();
            delayedHideAnim.restart();
        }
    }

    Timer {
        id: showTimer
        interval: showDelayMs
        onTriggered: {
            if (!showPill) {
                showAnim.start();
            }
        }
    }
}
