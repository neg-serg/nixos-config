# Quickshell media toast: how to do it right

Hard-won on odin. The rules below cover what not to repeat and how to make the toast compact,
pressed against the panel, and stable.

## Files

- files/quickshell/Widgets/SidePanel/MusicPopup.qml — the toast window/card.
- files/quickshell/Widgets/SidePanel/Music.qml — the content (cover art, metadata, progress,
  buttons).
- files/quickshell/Components/IPhoneSpectrum.qml — the analyzer (bars/led/wave).
- files/quickshell/Bar/Modules/Media.qml — the media capsule in the bar + mini preview.
- files/quickshell/Settings/Settings.qml — settings defaults.

## 1. Card position — the bottom of the card is the panel

- The MusicPopup window is a fullscreen WlrLayershell; the cardBox card is anchored bottom-right.
- The bottom margin hugs the panel (about 1px). computeBottomMargin() should return a small constant
  rather than baseMargin() + a large gap: function computeBottomMargin() { return Math.max(0,
  Math.round(1 * Theme.scale(Screen))); }
- Do NOT add a large gap `_bottomGapPx` (56 etc.) — it pulled the card away from the panel.
- The right-hand margin can remain baseMargin().

## 2. Card height — by content, not by a setting

- Do NOT force the card height from musicPopupHeight — the card came out tall while the content hung
  at the top with empty space below.
- The Music widget must not receive a fixed height: musicHeightPx — let it grow by its own
  implicitHeight (by content).
- computeCardHeight() takes the real content height musicWidget.implicitHeight; musicPopupHeight is
  used only as a fallback.
- After layout, recompute the height (the card hugs the content stably): Qt.callLater(function() {
  toast.cardHeightPx = toast.computeCardHeight(); });
- Cap against the real screen, NOT the height of the window itself: previously
  ScreenUtil.height(sidebarPopup) caused a loop (window → cap → card), and the card did not grow in
  height at all.

## 3. Content inside the card

- playerUI in Music.qml: anchors.bottom: parent.bottom — content is pressed to the bottom of the
  card (the cover ends up by the panel). Do NOT center vertically.
- verticalItemAlignment does not exist on ColumnLayout — it emits the warning 'Cannot assign to
  non-existent property'. Do not use it.
- Cover art and metadata column: Layout.alignment: Qt.AlignBottom, so the cover stands on the bottom
  edge of the card.

## 4. Analyzer: modes, colors, separators

- spectrumMode: bars | led | wave — these are DIFFERENT implementations (bars / LED segments /
  smooth wave). The \*AnalyserStyle presets are only color palettes layered on top of the
  implementation.
- spectrumColor (hex) — color override on top of the palette/cover; empty = preset/accent.
- Mini preview in the bar (Media.qml): flat, cover-art colored, thin (barGap: 4, minBarWidth: 1), no
  glow/threeD.
- Track title separator — «—» (mediaTitleSeparator); do NOT replace it with a slash. The time slash
  cur / total is already colored with the accent via Rich.sepSpan(accentCss, '/') — only recolor it,
  do not change the character.

## 5. Scrub bar (progress bar)

- Thin: musicPopupProgressHeight around 3 (logical px).
- Fill and bloom use the cover-art color (accent), not gray; the track hairline is also tinted with
  the accent (low alpha).
- The glow is a vertical bloom: anchor it to the bottom of the line and grow it upward (so it does
  not overlap the title below), at about 0.3 of the bar height.
- The bloom must not spread to the sides and must not depend on the length/width of the fill (when
  the card is stretched, the effect does not spread).

## 7. Backdrop — real blur, not the plugin's pseudo-frost

- The card is NOT in hyprglass's `layers.namespaces` any more: that pass frosts the wallpaper it
  re-samples instead of the surface's real backdrop. `qs-music` uses Hyprland's own layer blur
  (`blur-qs-.*`, `ignore_alpha 0.05`, live framebuffer) plus the card's translucent fill, so what
  shows through is what is really behind the popup.
- The frame is the thin 1 px hairline the card draws itself (`border.width: Theme.uiBorderWidth`,
  colour `sidePanelPopupGlassBorderOpacity`). Plate darkness: `sidePanelPopupGlassOpacity`.

## Settings (Settings.json)

- musicPopupWidth, musicPopupHeight (height is now only a fallback), musicPopupEdgeMargin,
  musicPopupProgressHeight.
- spectrumMode, spectrumColor, toastAnalyserStyle, barAnalyserStyle, mediaTitleSeparator.
- spectrumMinHz/MaxHz/ColorMinHz/ColorMaxHz — the frequency band and highlighting.
