import QtQuick
import QtQuick.Effects
import qs.Settings

// Soft shadow for glyphs that sit on glass (the media card's rows, the audio
// pills): a bright wallpaper behind a semi-transparent surface washes both the
// fill and the text out, and a shadow under the glyphs restores the reading
// without making the glass darker.
//
// A MultiEffect rather than `Text.style: Text.Raised`: QML ignores text styles
// for rich text, and the pills colourise their unit while the card decorates
// glyphs, so a layer effect is the only variant that covers every case.
//
// Usage: on any Text/icon item —
//
//   layer.enabled: Theme.textShadowEnabled
//   layer.effect: GlyphShadow {}
MultiEffect {
    shadowEnabled: true
    shadowColor: Theme.textShadow
    shadowOpacity: Theme.textShadowOpacity
    shadowBlur: 0.55
    shadowVerticalOffset: 1
    shadowHorizontalOffset: 0
    autoPaddingEnabled: true
}
