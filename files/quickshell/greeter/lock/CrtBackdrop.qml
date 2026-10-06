pragma ComponentBehavior: Bound
import QtQuick
import qs

// The CRT pass over a wallpaper item: barrel curve, chromatic aberration,
// scanlines, aperture grille, bloom and vignette (shaders/crt_screen.frag).
//
// The pass is still: the brightness sweep and the flicker are off unless the
// theme turns them on. Everything else here is a function of the pixel, so a
// screen with nothing to say does not repaint itself.
//
// It is deliberately *not* applied to the login card. Warping and resampling the
// scene costs more legibility than the effect is worth, so the card and its text
// are drawn on top of this, untouched; only pLinesOnly === 1 mode (scanlines,
// no warp, no bloom) is allowed over the UI.
ShaderEffect {
	id: root

	// The wallpaper to sample. Null in lines-only mode, where the pass draws
	// nothing but the lines and never reads the source.
	property Item backdrop: null

	property real pScanCount: Math.max(80, height / Math.max(GreeterTheme.crtLineSpacing, 1))
	property real pScanStrength: GreeterTheme.crtScanStrength
	property real pMaskStrength: GreeterTheme.crtMaskStrength
	property real pAberration: GreeterTheme.crtAberration
	property real pBarrel: GreeterTheme.crtBarrel
	property real pBloom: GreeterTheme.crtBloom
	property real pVignette: GreeterTheme.crtVignette
	property real pRollOffset: 0
	property real pRollStrength: GreeterTheme.crtRollStrength
	property real pFlicker: 1.0
	property real pLinesOnly: 0

	property Item source: backdropTexture

	fragmentShader: Qt.resolvedUrl("../shaders/crt_screen.frag.qsb")

	ShaderEffectSource {
		id: backdropTexture
		sourceItem: root.backdrop
		hideSource: GreeterTheme.crtEnabled && root.pLinesOnly < 0.5
		live: root.pLinesOnly < 0.5
		// Never drawn: only the effect output is visible.
		visible: false
	}

	// The brightness sweep is off unless the theme asks for it (crtRollStrength).
	// It is the only thing here that redraws the screen by itself, and a full-screen
	// pass that repaints every frame is exactly what makes a still login screen
	// look like it is shivering. With the roll at 0 the tube is a still picture.
	NumberAnimation on pRollOffset {
		from: 0
		to: 1
		duration: Math.max(1500, GreeterTheme.crtRollMs)
		loops: Animation.Infinite
		running: root.visible && root.pRollStrength > 0.001
	}
}
