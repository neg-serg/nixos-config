pragma Singleton
import QtQuick
import Quickshell
import "../Helpers/Color.js" as Color
import qs.Settings

// Single source of truth for notification colors.
// Every value is DERIVED from the shared shell Theme (qs.Settings.Theme)
// via Color.js formulas — no hardcoded literals, no per-file divergence.
// Card and Center both reference this singleton, so the style stays unified.
Singleton {
    id: root

    // Text: theme primary text, lightened (readable on the dark card).
    readonly property color fg: Color.towardsWhite(Theme.textPrimary, 0.4)
    // Accent: darker version of the theme accent (subtle frame/icon tint).
    readonly property color accent: Color.towardsBlack(Theme.accentPrimary, 0.3)
    // Surfaces: theme background at toast/panel opacity.
    readonly property color background: Color.withAlpha(Theme.background, 0.95)
    readonly property color panelBackground: Color.withAlpha(Theme.background, 0.92)
    // Action buttons: theme outline darkened for the fill, lighter on hover.
    readonly property color buttonNormal: Color.towardsBlack(Theme.outline, 0.55)
    readonly property color buttonHover: Color.towardsBlack(Theme.outline, 0.42)
    readonly property color outline: Theme.outline
}
