import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Settings
import qs.Components
import "../../Helpers/Color.js" as Color
import "../../Helpers/WeatherIcons.js" as WeatherIcons
import qs.Services as Services

Rectangle {
    id: weatherRoot
    width: Math.round(Theme.sidePanelWeatherWidth * 2 * Theme.scale(Screen) * weatherRoot.wscale)
    height: Math.round(Theme.sidePanelWeatherHeight * 2 * Theme.scale(Screen) * weatherRoot.wscale)
    color: "transparent"
    anchors.horizontalCenterOffset: Theme.weatherCenterOffset
    readonly property real wscale: 2.0

    property string city: Settings.settings.weatherCity !== undefined ? Settings.settings.weatherCity : ""
    property var weatherData: Services.Weather.weatherData
    property string errorString: Services.Weather.errorString
    property bool isVisible: false
    property int lastFetchTime: 0
    property bool isLoading: Services.Weather.isLoading

    readonly property var _cur: weatherData && weatherData.current ? weatherData.current : null
    readonly property int _wcode: _cur && typeof _cur.weather_code === 'number' ? _cur.weather_code : -1
    readonly property string _wicon: _wcode >= 0 ? WeatherIcons.materialSymbolForCode(_wcode) : "cloud"
    readonly property bool _useF: Settings.settings.useFahrenheit || false

    Connections { target: Services.Weather; function onWeatherDataChanged() { weatherRoot.weatherData = Services.Weather.weatherData } }
    Component.onCompleted: { if (isVisible) Services.Weather.start() }
    function startWeatherFetch() { isVisible = true; Services.Weather.start() }

    function warnContrast(bg, fg, label) {
        try {
            if (!(Settings.settings && Settings.settings.debugLogs)) return;
            var ratio = Color.contrastRatio(bg, fg);
            var th = (Settings.settings && Settings.settings.contrastWarnRatio) ? Settings.settings.contrastWarnRatio : 4.5;
            if (ratio < th) console.debug('[Contrast]', label || 'text', 'ratio', ratio.toFixed(2));
        } catch (e) { console.warn("[Weather.warnContrast]", e) }
    }

    Rectangle {
        id: card
        anchors.fill: parent
        color: Color.withAlpha("#000000", 0.85)
        border.color: "transparent"
        radius: Math.round(Theme.sidePanelCornerRadius * Theme.scale(Screen) * weatherRoot.wscale)
        clip: true

        Rectangle { anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; height: 1; color: Color.withAlpha(Theme.accentPrimary, 0.25); z: 2 }

        Canvas {
            id: weatherDecor
            anchors.fill: parent
            z: 0
            property int wcode: weatherRoot._wcode
            onWcodeChanged: requestPaint()

            onPaint: {
                var ctx = getContext("2d");
                ctx.reset();
                ctx.globalAlpha = 0.07;
                var w = width, h = height;

                if (wcode === 0) {
                    drawSunRays(ctx, w, h);
                } else if (wcode >= 1 && wcode <= 3) {
                    drawSunRays(ctx, w, h);
                    drawClouds(ctx, w, h);
                } else if (wcode >= 45 && wcode <= 48) {
                    drawFog(ctx, w, h);
                } else if (wcode >= 51 && wcode <= 67 || wcode >= 80 && wcode <= 82) {
                    drawRain(ctx, w, h);
                } else if (wcode >= 71 && wcode <= 77) {
                    drawSnow(ctx, w, h);
                } else if (wcode >= 95 && wcode <= 99) {
                    drawRain(ctx, w, h);
                    drawStormBolt(ctx, w, h);
                }

                // Always draw moon phase in bottom-right
                drawMoon(ctx, w, h);
            }

            function drawSunRays(ctx, w, h) {
                var cx=w*0.7,cy=h*0.3,r=Math.min(w,h)*0.1;
                ctx.globalCompositeOperation="lighter";
                // Particle corona — 360 radial beams
                for(var i=0;i<360;i++){
                    var a=Math.PI*2*i/360;
                    var len=r*(1.2+Math.abs(Math.sin(i*4.7))*0.8+Math.abs(Math.sin(i*13))*0.4);
                    var al=0.3+Math.abs(Math.sin(i*7))*0.4+Math.abs(Math.sin(i*19))*0.3;
                    ctx.globalAlpha=al*0.3;
                    ctx.strokeStyle=Theme.accentPrimary;ctx.lineWidth=1+Math.random()*2;
                    ctx.beginPath();ctx.moveTo(cx+Math.cos(a)*r*0.7,cy+Math.sin(a)*r*0.7);
                    ctx.lineTo(cx+Math.cos(a)*len,cy+Math.sin(a)*len);ctx.stroke();}
                // Core glow
                ctx.globalAlpha=0.9;ctx.fillStyle=Color.withAlpha("#ffffff",0.95);
                ctx.beginPath();ctx.arc(cx,cy,r*0.35,0,Math.PI*2);ctx.fill();
                var grd=ctx.createRadialGradient(cx,cy,r*0.2,cx,cy,r*1.1);
                grd.addColorStop(0,Color.withAlpha(Theme.accentPrimary,0.9));
                grd.addColorStop(0.3,Color.withAlpha(Theme.accentPrimary,0.6));
                grd.addColorStop(0.6,Color.withAlpha(Theme.accentPrimary,0.2));
                grd.addColorStop(1,"transparent");
                ctx.globalAlpha=0.7;ctx.fillStyle=grd;
                ctx.beginPath();ctx.arc(cx,cy,r*1.1,0,Math.PI*2);ctx.fill();
                ctx.globalCompositeOperation="source-over";}

            function drawMoon(ctx, w, h) {
                var age=WeatherIcons.moonAge(new Date());
                var cx=w*0.78,cy=h*0.72,r=Math.min(w,h)*0.13;
                ctx.globalCompositeOperation="source-over";
                // Outer glow — scattered particles
                ctx.globalAlpha=0.06;
                for(var i=0;i<80;i++){
                    var a=Math.random()*Math.PI*2;
                    var d=r*(1.1+Math.random()*0.7);
                    var sz=1+Math.random()*3;
                    ctx.fillStyle=Theme.accentPrimary;
                    ctx.beginPath();ctx.arc(cx+Math.cos(a)*d,cy+Math.sin(a)*d,sz,0,Math.PI*2);ctx.fill();}
                // Moon surface
                var surf=ctx.createRadialGradient(cx-r*0.25,cy-r*0.25,r*0.05,cx,cy,r);
                surf.addColorStop(0,Color.withAlpha("#f0e8d8",0.95));
                surf.addColorStop(0.5,Color.withAlpha("#c8b898",0.9));
                surf.addColorStop(1,Color.withAlpha("#706050",0.7));
                ctx.globalAlpha=1;ctx.fillStyle=surf;
                ctx.beginPath();ctx.arc(cx,cy,r,0,Math.PI*2);ctx.fill();
                // Detailed craters
                var craters=[[-0.35,-0.15,0.11],[-0.05,-0.45,0.08],[0.3,0.1,0.09],[-0.2,0.35,0.07],[0.5,-0.25,0.06],[0.15,0.45,0.05],[-0.5,0.2,0.05],[0,-0.05,0.03],[0.4,-0.5,0.04],[-0.3,-0.35,0.04],[0.55,0,0.04],[-0.45,-0.4,0.03],[0.25,0.3,0.06],[-0.1,0.15,0.05],[0.35,-0.1,0.04]];
                craters.forEach(function(c){
                    ctx.globalAlpha=0.06;ctx.fillStyle="#000000";
                    ctx.beginPath();ctx.arc(cx+r*c[0]+1,cy+r*c[1]+1,r*c[2],0,Math.PI*2);ctx.fill();
                    ctx.globalAlpha=0.04;ctx.fillStyle="#ffffff";
                    ctx.beginPath();ctx.arc(cx+r*c[0]-1,cy+r*c[1]-1,r*c[2]*0.7,0,Math.PI*2);ctx.fill();});
                // Phase shadow
                var sa=age*Math.PI*2;var sx=cx+Math.cos(sa)*r*1.05;
                var sg=ctx.createRadialGradient(sx,cy,r*0.05,sx,cy,r*1.1);
                sg.addColorStop(0,Color.withAlpha("#000000",0.92));sg.addColorStop(0.6,Color.withAlpha("#000000",0.4));sg.addColorStop(1,"transparent");
                ctx.globalAlpha=1;ctx.fillStyle=sg;
                ctx.beginPath();ctx.arc(sx,cy,r*1.1,0,Math.PI*2);ctx.fill();
                // Limb highlight
                ctx.globalAlpha=0.15;ctx.strokeStyle=Color.withAlpha(Theme.accentPrimary,0.6);ctx.lineWidth=0.5;
                ctx.beginPath();ctx.arc(cx,cy,r,0,Math.PI*2);ctx.stroke();}
            }

            function drawCloud(ctx, cx, cy, r) {
                ctx.beginPath();
                ctx.arc(cx, cy, r, 0, Math.PI * 2);
                ctx.arc(cx + r * 0.7, cy - r * 0.25, r * 0.75, 0, Math.PI * 2);
                ctx.arc(cx + r * 1.2, cy, r * 0.7, 0, Math.PI * 2);
                ctx.arc(cx - r * 0.6, cy + r * 0.1, r * 0.6, 0, Math.PI * 2);
                ctx.arc(cx + r * 0.5, cy - r * 0.5, r * 0.55, 0, Math.PI * 2);
                ctx.fill();
            }

            function drawFog(ctx, w, h) {
                ctx.strokeStyle = "#8899AA";
                ctx.lineWidth = 2;
                for (var i = 0; i < 6; i++) {
                    var y = h * 0.2 + i * h * 0.1;
                    ctx.globalAlpha = 0.04 + i * 0.006;
                    ctx.beginPath();
                    ctx.moveTo(w * 0.1, y);
                    ctx.lineTo(w * 0.9, y);
                    ctx.stroke();
                }
                ctx.globalAlpha = 0.07;
            }

            function drawRain(ctx, w, h) {
                ctx.strokeStyle = "#88AACC";
                ctx.lineWidth = 1;
                for (var i = 0; i < 40; i++) {
                    var x = (i * 37 + 13) % w;
                    var y = (i * 53 + 7) % h;
                    ctx.beginPath();
                    ctx.moveTo(x, y);
                    ctx.lineTo(x - 3, y + 8);
                    ctx.stroke();
                }
            }

            function drawSnow(ctx, w, h) {
                ctx.fillStyle = "#CCDDEE";
                for (var i = 0; i < 30; i++) {
                    var x = (i * 47 + 13) % w;
                    var y = (i * 59 + 7) % h;
                    var r = 1.5 + (i % 3) * 1;
                    ctx.beginPath();
                    ctx.arc(x, y, r, 0, Math.PI * 2);
                    ctx.fill();
                }
            }

            function drawStormBolt(ctx, w, h) {
                ctx.strokeStyle = "#FFD040";
                ctx.lineWidth = 2.5;
                ctx.beginPath();
                var bx = w * 0.75, by = h * 0.08;
                ctx.moveTo(bx, by);
                ctx.lineTo(bx - 10, by + 22);
                ctx.lineTo(bx + 4, by + 22);
                ctx.lineTo(bx - 8, by + 44);
                ctx.stroke();
            }

        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Math.round(Theme.panelSideMargin * 0.9 * Theme.scale(Screen) * weatherRoot.wscale)
            spacing: Math.round(Theme.sidePanelSpacingSmall * Theme.scale(Screen) * weatherRoot.wscale)
            z: 1

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.round(Theme.uiIconSizeLarge * Theme.scale(Screen) * weatherRoot.wscale)
                spacing: Math.round(Theme.sidePanelSpacing * Theme.scale(Screen) * weatherRoot.wscale)

                Spinner {
                    id: loadingSpinner
                    running: isLoading
                    color: Theme.accentPrimary
                    size: Math.round(Theme.uiIconSizeLarge * Theme.scale(Screen) * weatherRoot.wscale)
                    visible: isLoading
                    Layout.alignment: Qt.AlignVCenter
                }

                MaterialIcon {
                    id: weatherIcon
                    visible: !isLoading
                    icon: weatherRoot._wicon
                    size: Math.round(Theme.uiIconSizeLarge * 1.1 * Theme.scale(Screen) * weatherRoot.wscale)
                    color: Theme.accentPrimary
                    Layout.alignment: Qt.AlignVCenter
                }

                Text {
                    text: weatherData && weatherData.current
                        ? (_useF ? Math.round(weatherData.current.temperature_2m * 9/5 + 32) + "°F" : Math.round(weatherData.current.temperature_2m) + "°C")
                        : (_useF ? "--°F" : "--°C")
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.round(Theme.fontSizeHeader * Theme.weatherHeaderScale * 1.15 * Theme.scale(Screen) * weatherRoot.wscale)
                    font.bold: true
                    color: Theme.textOn(card.color)
                    Layout.alignment: Qt.AlignVCenter
                    Component.onCompleted: weatherRoot.warnContrast(card.color, color, 'weather.temp')
                }

                ColumnLayout {
                    spacing: 1
                    Layout.alignment: Qt.AlignVCenter

                    Text {
                        text: city.length > 18 ? city.slice(0, 17) + "\u2026" : city
                        font.family: Theme.fontFamily
                        font.pixelSize: Math.round(Theme.fontSizeSmall * Theme.scale(Screen) * weatherRoot.wscale)
                        font.bold: true
                        color: Theme.textOn(card.color)
                        elide: Text.ElideRight
                    }
                    Text {
                        text: weatherData && weatherData.timezone_abbreviation ? weatherData.timezone_abbreviation : ""
                        font.family: Theme.fontFamily
                        font.pixelSize: Math.round(Theme.tooltipFontPx * Theme.tooltipSmallScaleRatio * Theme.scale(Screen) * weatherRoot.wscale)
                        color: Theme.textSecondary
                        visible: text !== ""
                    }
                }

                Item { Layout.fillWidth: true }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Math.round(Theme.sidePanelSpacing * Theme.scale(Screen) * weatherRoot.wscale)
                visible: weatherData && weatherData.current

                RowLayout {
                    spacing: 4
                    visible: weatherRoot._cur && typeof weatherRoot._cur.wind_speed_10m === 'number' && weatherRoot._cur.wind_speed_10m > 0.1
                    MaterialIcon {
                        icon: "navigation"
                        rotationAngle: WeatherIcons.windRotation(weatherRoot._cur ? weatherRoot._cur.wind_direction_10m : 0)
                        size: Math.round(Theme.fontSizeSmall * 0.85 * Theme.scale(Screen) * weatherRoot.wscale)
                        color: Theme.textOn(card.color)
                    }
                    Text {
                        text: weatherRoot._cur ? WeatherIcons.formatWindFull(weatherRoot._cur.wind_speed_10m, weatherRoot._cur.wind_direction_10m) : ""
                        font.family: Theme.fontFamily
                        font.pixelSize: Math.round(Theme.fontSizeSmall * 0.85 * Theme.scale(Screen) * weatherRoot.wscale)
                        color: Theme.textOn(card.color)
                    }
                }

                RowLayout {
                    spacing: 4
                    visible: weatherRoot._cur && typeof weatherRoot._cur.relative_humidity_2m === 'number'
                    MaterialIcon {
                        icon: "water_drop"
                        size: Math.round(Theme.fontSizeSmall * 0.85 * Theme.scale(Screen) * weatherRoot.wscale)
                        color: Theme.textOn(card.color)
                    }
                    Text {
                        text: weatherRoot._cur ? Math.round(weatherRoot._cur.relative_humidity_2m) + "%" : ""
                        font.family: Theme.fontFamily
                        font.pixelSize: Math.round(Theme.fontSizeSmall * 0.85 * Theme.scale(Screen) * weatherRoot.wscale)
                        color: Theme.textOn(card.color)
                    }
                }

                RowLayout {
                    spacing: 4
                    MoonPhaseIcon {
                        size: Math.round(Theme.fontSizeSmall * 0.85 * Theme.scale(Screen) * weatherRoot.wscale)
                        moonColor: Theme.textOn(card.color)
                        rimColor: Color.withAlpha(Theme.textOn(card.color), 0.5)
                    }
                    Text {
                        text: WeatherIcons.moonName(new Date())
                        font.family: Theme.fontFamily
                        font.pixelSize: Math.round(Theme.fontSizeSmall * 0.85 * Theme.scale(Screen) * weatherRoot.wscale)
                        color: Theme.textOn(card.color)
                    }
                    Text {
                        text: Math.round(WeatherIcons.moonIllumination(new Date())) + "%"
                        font.family: Theme.fontFamily
                        font.pixelSize: Math.round(Theme.fontSizeSmall * 0.7 * Theme.scale(Screen) * weatherRoot.wscale)
                        color: Theme.textSecondary
                    }
                }

                Item { Layout.fillWidth: true }
            }

            RowLayout {
                spacing: Math.round(Theme.sidePanelSpacing * Theme.scale(Screen) * weatherRoot.wscale)
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 2
                visible: weatherData && weatherData.daily && weatherData.daily.time

                Repeater {
                    model: weatherData && weatherData.daily && weatherData.daily.time ? Math.min(5, weatherData.daily.time.length) : 0
                    delegate: ColumnLayout {
                        spacing: 1
                        Layout.alignment: Qt.AlignHCenter

                        Text {
                            text: weatherData.daily.time[index] ? Qt.formatDateTime(new Date(weatherData.daily.time[index]), "ddd") : ""
                            font.family: Theme.fontFamily
                            font.pixelSize: Math.round(Theme.fontSizeCaption * Theme.scale(Screen) * weatherRoot.wscale)
                            color: Theme.textOn(card.color)
                            horizontalAlignment: Text.AlignHCenter
                            Layout.alignment: Qt.AlignHCenter
                        }

                        MaterialIcon {
                            icon: weatherData.daily.weathercode && weatherData.daily.weathercode[index] !== undefined
                                ? WeatherIcons.materialSymbolForCode(weatherData.daily.weathercode[index]) : "cloud"
                            size: Math.round(Theme.panelPillIconSize * 0.9 * Theme.scale(Screen) * weatherRoot.wscale)
                            color: Theme.accentPrimary
                            Layout.alignment: Qt.AlignHCenter
                        }

                        Text {
                            text: weatherData && weatherData.daily && weatherData.daily.temperature_2m_max
                                ? (_useF ? Math.round(weatherData.daily.temperature_2m_max[index] * 9/5 + 32) + "°" : Math.round(weatherData.daily.temperature_2m_max[index]) + "°")
                                : "--°"
                            font.family: Theme.fontFamily
                            font.pixelSize: Math.round(Theme.fontSizeCaption * Theme.scale(Screen) * weatherRoot.wscale)
                            font.bold: true
                            color: Theme.textPrimary
                            horizontalAlignment: Text.AlignHCenter
                            Layout.alignment: Qt.AlignHCenter
                        }

                        Text {
                            text: weatherData && weatherData.daily && weatherData.daily.temperature_2m_min
                                ? (_useF ? Math.round(weatherData.daily.temperature_2m_min[index] * 9/5 + 32) + "°" : Math.round(weatherData.daily.temperature_2m_min[index]) + "°")
                                : "--°"
                            font.family: Theme.fontFamily
                            font.pixelSize: Math.round(Theme.fontSizeCaption * 0.85 * Theme.scale(Screen) * weatherRoot.wscale)
                            color: Color.withAlpha(Theme.textPrimary, 0.65)
                            horizontalAlignment: Text.AlignHCenter
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }
                }
            }

            Text {
                text: errorString
                color: Theme.error
                visible: errorString !== ""
                font.family: Theme.fontFamily
                font.pixelSize: Math.round(Theme.tooltipFontPx * 0.71 * Theme.scale(Screen) * weatherRoot.wscale)
                horizontalAlignment: Text.AlignHCenter
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }
}
