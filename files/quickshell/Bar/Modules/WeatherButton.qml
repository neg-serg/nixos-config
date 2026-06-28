import QtQuick
import qs.Components
import qs.Settings
import qs.Widgets.SidePanel
import qs.Services as Services
import "../../Helpers/TooltipText.js" as TooltipText
import "../../Helpers/WeatherIcons.js" as WeatherIcons

OverlayToggleCapsule {
    id: root
    readonly property real capsuleScale: capsule.capsuleScale
    readonly property int iconBox: capsule.capsuleInner
    capsule.backgroundKey: "weather"
    capsule.centerContent: true
    capsule.cursorShape: Qt.PointingHandCursor
    capsule.implicitWidth: capsule.horizontalPadding * 2 + weatherContent.implicitWidth
    capsuleVisible: true
    autoToggleOnTap: true
    overlayNamespace: "sideleft-weather"

    Component.onCompleted: Services.Weather.start()

    readonly property var _weatherData: Services.Weather.weatherData
    readonly property var _current: _weatherData && _weatherData.current ? _weatherData.current : null
    readonly property string weatherIcon: _current && typeof _current.weather_code === 'number'
        ? WeatherIcons.materialSymbolForCode(_current.weather_code)
        : "partly_cloudy_day"
    readonly property string temperatureText: {
        try {
            if (_current && typeof _current.temperature_2m === 'number') {
                var c = Math.round(_current.temperature_2m);
                var useF = Settings.settings.useFahrenheit || false;
                return useF ? Math.round(c * 9/5 + 32) + "°F" : c + "°C";
            }
        } catch (e) {}
        return (Settings.settings.useFahrenheit || false) ? "--°F" : "--°C";
    }
    readonly property bool hasWind: _current && typeof _current.wind_speed_10m === 'number'
    readonly property string windSpeed: {
        try { if (hasWind) return WeatherIcons.formatWindSpeed(_current.wind_speed_10m); } catch (e) {}
        return "";
    }
    readonly property real windRotation: {
        try { if (hasWind) return WeatherIcons.windRotation(_current.wind_direction_10m); } catch (e) {}
        return 0;
    }
    readonly property bool hasHumidity: _current && typeof _current.relative_humidity_2m === 'number'
    readonly property string humidityText: {
        try { if (hasHumidity) return Math.round(_current.relative_humidity_2m) + "%"; } catch (e) {}
        return "";
    }

    Row {
        id: weatherContent
        anchors.centerIn: parent
        spacing: Math.round(4 * capsuleScale)

        MaterialIcon {
            id: weatherIconItem
            icon: root.weatherIcon
            size: iconBox
            color: Theme.accentPrimary
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            id: tempLabel
            text: root.temperatureText
            font.family: Theme.fontFamily
            font.pixelSize: Math.round(Theme.fontSizeSmall * capsuleScale)
            color: Theme.textPrimary
            anchors.verticalCenter: parent.verticalCenter
        }

        MaterialIcon {
            id: humidityIcon
            icon: "water_drop"
            size: Math.round(Theme.fontSizeSmall * capsuleScale * 0.85)
            color: root.hasHumidity ? Theme.textSecondary : Theme.textDisabled
            anchors.verticalCenter: parent.verticalCenter
            Behavior on color { ColorFastInOutBehavior {} }
        }

        Text {
            id: humidityLabel
            visible: root.hasHumidity
            text: root.humidityText
            font.family: Theme.fontFamily
            font.pixelSize: Math.round(Theme.fontSizeSmall * capsuleScale * 0.85)
            color: Theme.textSecondary
            anchors.verticalCenter: parent.verticalCenter
        }

        MaterialIcon {
            id: windArrow
            icon: "navigation"
            rotationAngle: root.windRotation
            size: Math.round(Theme.fontSizeSmall * capsuleScale * 0.85)
            color: root.hasWind ? Theme.textSecondary : Theme.textDisabled
            anchors.verticalCenter: parent.verticalCenter
            Behavior on color { ColorFastInOutBehavior {} }
        }

        Text {
            id: windLabel
            visible: root.hasWind
            text: root.windSpeed
            font.family: Theme.fontFamily
            font.pixelSize: Math.round(Theme.fontSizeSmall * capsuleScale * 0.85)
            color: Theme.textSecondary
            anchors.verticalCenter: parent.verticalCenter
        }

        MoonPhaseIcon {
            id: moonIcon
            size: Math.round(Theme.fontSizeSmall * capsuleScale)
            moonColor: Theme.textSecondary
            rimColor: Theme.textDisabled
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    HoverHandler {
        id: hoverArea
    }

    overlayChildren: [
        PanelOverlaySurface {
            id: popup
            screen: root.screen
            scaleHint: capsuleScale
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: Math.round((Theme.panelModuleHeight + 4) * capsuleScale)

            Weather {
                id: weather
                width: Math.round(Theme.sidePanelWeatherWidth * capsuleScale)
                height: Math.round(Theme.sidePanelWeatherHeight * capsuleScale)
            }
        }
    ]

    PanelTooltip {
        id: weatherTip
        targetItem: weatherContent
        text: root.tooltipText()
        visibleWhen: hoverArea.hovered
    }

    function tooltipText() {
        try {
            const city = Settings.settings.weatherCity || "";
            const data = Services.Weather.weatherData;
            const cur = data && data.current ? data.current : null;
            if (cur && typeof cur.temperature_2m === 'number') {
                const c = Math.round(cur.temperature_2m);
                const useF = Settings.settings.useFahrenheit || false;
                const t = useF ? Math.round(c * 9/5 + 32) + "°F" : c + "°C";
                const wind = WeatherIcons.formatWindFull(cur.wind_speed_10m, cur.wind_direction_10m);
                var sub = wind ? [wind] : [];
                if (typeof cur.relative_humidity_2m === 'number')
                    sub.push("Humidity: " + Math.round(cur.relative_humidity_2m) + "%");
                sub.push("Moon: " + WeatherIcons.moonName(new Date()));
                return TooltipText.compose(city || "Weather", t, sub);
            }
            return TooltipText.compose("Weather", city, []);
        } catch (e) {
            return "Weather";
        }
    }

    Connections { target: Services.Weather; function onWeatherDataChanged() { weatherTip.text = root.tooltipText(); } }
}
