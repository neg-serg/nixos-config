pragma ComponentBehavior: Bound
import QtQuick
import qs

// Wraps a text layer with a halo: an accent glow plus a dark, slightly offset
// shadow, both rendered from the layer's own alpha by shaders/text_glow.frag,
// with the sharp layer drawn on top (a copy of the same texture, so nothing is
// re-rasterised). Declare the text items as children — they keep their ids:
//
//     TextGlow {
//         ColumnLayout { id: cardLayout; ... }
//     }
Item {
	id: root

	default property alias content: container.data

	property color glowColour: GreeterTheme.textGlowColour
	property real glowStrength: GreeterTheme.textGlow
	property real glowRadius: GreeterTheme.textGlowRadius
	property color shadowColour: GreeterTheme.textShadowColour
	property real shadowStrength: GreeterTheme.textShadow
	property vector2d shadowOffset: Qt.vector2d(0, GreeterTheme.textShadowOffset)


	ShaderEffectSource {
		id: layerTexture
		sourceItem: container
		hideSource: false   // the container is drawn itself, on top of the halos
		live: true
		smooth: true
	}

	ShaderEffect {
		anchors.fill: parent
		visible: root.glowStrength > 0.001
		property Item source: layerTexture
		property vector2d pOffset: Qt.vector2d(0, 0)
		property real pRadius: root.glowRadius
		property real pStrength: root.glowStrength
		property color pColour: root.glowColour
		property vector2d pTexel: Qt.vector2d(1.0 / Math.max(width, 1), 1.0 / Math.max(height, 1))
		fragmentShader: Qt.resolvedUrl("../shaders/text_glow.frag.qsb")
	}

	ShaderEffect {
		anchors.fill: parent
		visible: root.shadowStrength > 0.001
		property Item source: layerTexture
		property vector2d pOffset: root.shadowOffset
		property real pRadius: GreeterTheme.textShadowRadius
		property real pStrength: root.shadowStrength
		property color pColour: root.shadowColour
		property vector2d pTexel: Qt.vector2d(1.0 / Math.max(width, 1), 1.0 / Math.max(height, 1))
		fragmentShader: Qt.resolvedUrl("../shaders/text_glow.frag.qsb")
	}

	// Draw order: layerTexture feeds the halos (declared above), the halos are drawn,
	// and the content itself comes after them — on top, untouched.
	// The layer itself. It is rendered into a texture for the two halo passes and
	// then drawn normally, so the sharp text is the real item, not a resampled copy.
	Item {
		id: container
		anchors.fill: parent
	}

}
