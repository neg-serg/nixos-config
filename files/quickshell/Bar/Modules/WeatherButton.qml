
import QtQuick
import qs.Components
import Quickshell.Wayland
import qs.Settings
import qs.Widgets.SidePanel
import qs.Services as Services
import "../../Helpers/TooltipText.js" as TooltipText

OverlayToggleCapsule {
    id: root
    readonly property real capsuleScale: capsule.capsuleScale
    readonly property int iconBox: capsule.capsuleInner
    capsule.backgroundKey: "weather"
    capsule.centerContent: true
    capsule.cursorShape: Qt.PointingHandCursor
    capsuleVisible: true
    autoToggleOnTap: false
    overlayNamespace: "sideleft-weather"
    onOpened: { try { Services.Weather.start(); } catch (e) {} }
    onDismissed: { try { Services.Weather.stop(); } catch (e) {} }

    PanelIconButton {
        id: weatherBtn
        anchors.centerIn: parent
        size: iconBox
        icon: "partly_cloudy_day"
        onClicked: root.toggle("weather")
        hoverEnabled: true
        onEntered: {
            try { weather.startWeatherFetch(); } catch (e) {}
        }
    }

    overlayChildren: [
        PanelOverlaySurface {
            id: popup
            screen: root.screen
            scaleHint: capsuleScale
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.topMargin: Math.round(Theme.sidePanelSpacingMedium * capsuleScale)
            anchors.leftMargin: Math.round(Theme.panelSideMargin * capsuleScale)

            Weather {
                id: weather
                width: Math.round(Theme.sidePanelWeatherWidth * capsuleScale)
                height: Math.round(Theme.sidePanelWeatherHeight * capsuleScale)
            }
        }
    ]

    PanelTooltip {
        id: weatherTip
        targetItem: weatherBtn
        text: root.tooltipText()
        visibleWhen: weatherBtn.hovering
    }

    function tooltipText() {
        try {
            const city = Settings.settings.weatherCity || "";
            const data = Services.Weather.weatherData;
            if (data && data.current_weather && typeof data.current_weather.temperature === 'number') {
                const c = Math.round(data.current_weather.temperature);
                const useF = Settings.settings.useFahrenheit || false;
                const t = useF ? Math.round(c * 9/5 + 32) + "°F" : c + "°C";
                return TooltipText.compose(city || "Weather", t, []);
            }
            return TooltipText.compose("Weather", city, []);
        } catch (e) {
            return "Weather";
        }
    }

    Connections { target: Services.Weather; function onWeatherDataChanged() { weatherTip.text = root.tooltipText(); } }
}
