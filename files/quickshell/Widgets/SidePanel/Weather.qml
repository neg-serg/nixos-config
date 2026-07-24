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
    implicitWidth: contentLayout.implicitWidth + 2 * contentLayout.anchors.margins
    implicitHeight: contentLayout.implicitHeight + 2 * contentLayout.anchors.margins
    color: "transparent"
    anchors.horizontalCenterOffset: Theme.weatherCenterOffset
    readonly property real wscale: 2.1
    readonly property color cardBg: Color.withAlpha(Theme.accentPrimary, 0.06)

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

    function warnContrast(bg, fg, label) { try { if(!(Settings.settings&&Settings.settings.debugLogs))return;var r=Color.contrastRatio(bg,fg);var t=(Settings.settings&&Settings.settings.contrastWarnRatio)?Settings.settings.contrastWarnRatio:4.5;if(r<t)console.debug('[Contrast]',label||'text','ratio',r.toFixed(2)) } catch(e){console.warn("[Weather.warnContrast]",e)} }

    Rectangle {
        id: card
        anchors.fill: parent
        color: Color.withAlpha(Theme.surface, 0.85)
        border.color: "transparent"
        border.width: 0
        radius: 0
        clip: true

        Rectangle { anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; height: 1; color: Color.withAlpha(Theme.accentPrimary, 0.25); z: 3 }

        Canvas {
            id: weatherDecor
            anchors.fill: parent; z: 0
            property int wcode: weatherRoot._wcode
            onWcodeChanged: requestPaint()

            onPaint: {
                var ctx=getContext("2d");ctx.reset();ctx.globalAlpha=0.25
                var w=width,h=height
                if(wcode>=1&&wcode<=3)drawClouds(ctx,w,h)
                else if(wcode>=45&&wcode<=48)drawFog(ctx,w,h)
                else if(wcode>=51&&wcode<=67||wcode>=80&&wcode<=82)drawRain(ctx,w,h)
                else if(wcode>=71&&wcode<=77)drawSnow(ctx,w,h)
                else if(wcode>=95&&wcode<=99){drawRain(ctx,w,h);drawStormBolt(ctx,w,h)}
            }
            Timer { interval: 33; repeat: true; running: true; onTriggered: weatherDecor.requestPaint() }

            function drawClouds(ctx,w,h){ctx.fillStyle="rgba(170,187,204,0.85)";drawCloud(ctx,w*0.15,h*0.16,12);drawCloud(ctx,w*0.13,h*0.14,11);drawCloud(ctx,w*0.16,h*0.15,9)}
            function drawCloud(ctx,cx,cy,r){ctx.beginPath();ctx.arc(cx,cy,r,0,Math.PI*2);ctx.arc(cx+r*0.7,cy-r*0.25,r*0.75,0,Math.PI*2);ctx.arc(cx+r*1.2,cy,r*0.7,0,Math.PI*2);ctx.arc(cx-r*0.6,cy+r*0.1,r*0.6,0,Math.PI*2);ctx.arc(cx+r*0.5,cy-r*0.5,r*0.55,0,Math.PI*2);ctx.fill()}
            function drawFog(ctx,w,h){ctx.strokeStyle="#8899AA";ctx.lineWidth=2;for(var i=0;i<6;i++){var y=h*0.2+i*h*0.1;ctx.globalAlpha=0.04+i*0.006;ctx.beginPath();ctx.moveTo(w*0.1,y);ctx.lineTo(w*0.9,y);ctx.stroke()}ctx.globalAlpha=0.07}
            function drawRain(ctx,w,h){ctx.strokeStyle="#88AACC";ctx.lineWidth=1;for(var i=0;i<40;i++){var x=(i*37+13)%w;var y=(i*53+7)%h;ctx.beginPath();ctx.moveTo(x,y);ctx.lineTo(x-3,y+8);ctx.stroke()}}
            function drawSnow(ctx,w,h){ctx.fillStyle="#CCDDEE";for(var i=0;i<30;i++){var x=(i*47+13)%w;var y=(i*59+7)%h;var r2=1.5+(i%3)*1;ctx.beginPath();ctx.arc(x,y,r2,0,Math.PI*2);ctx.fill()}}
            function drawStormBolt(ctx,w,h){ctx.strokeStyle="#FFD040";ctx.lineWidth=2;ctx.beginPath();var bx=w*0.75,by=h*0.20;ctx.moveTo(bx,by);ctx.lineTo(bx-8,by+16);ctx.lineTo(bx+3,by+16);ctx.lineTo(bx-6,by+32);ctx.stroke()}
        }

        ColumnLayout {
            id: contentLayout
            anchors.fill: parent
            anchors.margins: Math.round(Theme.panelSideMargin * 2.0 * Theme.scale(Screen) * weatherRoot.wscale)
            spacing: Math.round(Theme.sidePanelSpacing * Theme.scale(Screen) * weatherRoot.wscale)
            z: 2

            readonly property real cardPad: Math.round(Theme.sidePanelSpacingSmall * Theme.scale(Screen) * weatherRoot.wscale)
            readonly property real cardRadius: 3

            // ── Current conditions card ──
            Item {
                Layout.fillWidth: true
                implicitWidth: currentRow.implicitWidth + 2 * contentLayout.cardPad
                implicitHeight: currentRow.implicitHeight + 2 * contentLayout.cardPad
                Rectangle {
                    anchors.fill: parent
                    color: weatherRoot.cardBg
                    radius: contentLayout.cardRadius
                    z: 0
                }
                RowLayout {
                    id: currentRow
                    anchors.fill: parent
                    anchors.margins: contentLayout.cardPad
                    spacing: Math.round(Theme.sidePanelSpacing * Theme.scale(Screen) * weatherRoot.wscale)
                    z: 1
                    Spinner { id: loadingSpinner; running: isLoading; color: Theme.accentPrimary; size: Math.round(Theme.uiIconSizeLarge * Theme.scale(Screen) * weatherRoot.wscale); visible: isLoading; Layout.alignment: Qt.AlignVCenter }
                Canvas { id: sunIcon; visible: !isLoading; width: Math.round(Theme.uiIconSizeLarge*1.5*Theme.scale(Screen)*weatherRoot.wscale); height: width; Layout.alignment: Qt.AlignVCenter; onPaint: {var ctx=getContext("2d");ctx.reset();var s=width,r=s*0.30;var cx=s/2,cy=s/2;var t=Date.now()*0.001;var grd=ctx.createRadialGradient(cx,cy,r*0.05,cx,cy,r*1.5);grd.addColorStop(0,"rgba(255,255,255,1)");grd.addColorStop(0.12,"rgba(255,255,240,0.95)");grd.addColorStop(0.35,Color.withAlpha(Theme.accentPrimary,0.5));grd.addColorStop(0.65,Color.withAlpha(Theme.accentPrimary,0.1));grd.addColorStop(1,"transparent");ctx.fillStyle=grd;ctx.beginPath();ctx.arc(cx,cy,r*1.5,0,Math.PI*2);ctx.fill();ctx.globalCompositeOperation="lighter";for(var i=0;i<360;i++){var a=Math.PI*2*i/360;var wig=Math.sin(i*4.7+t*0.8)*0.35+Math.sin(i*13.3-t*0.5)*0.2+Math.sin(i*21.1+t*1.1)*0.12;var len=r*(0.5+wig);var al=0.15+Math.abs(wig)*0.7;ctx.globalAlpha=al*0.3;ctx.strokeStyle=Theme.accentPrimary;ctx.lineWidth=0.4+Math.abs(Math.sin(i*23.7+t*3.1))*1.0;ctx.beginPath();ctx.moveTo(cx+Math.cos(a)*r*0.25,cy+Math.sin(a)*r*0.25);ctx.lineTo(cx+Math.cos(a)*len,cy+Math.sin(a)*len);ctx.stroke()}ctx.globalCompositeOperation="source-over"} Timer { interval: 50; repeat: true; running: true; onTriggered: sunIcon.requestPaint() } }
                    Text { text: weatherData&&weatherData.current?(_useF?Math.round(weatherData.current.temperature_2m*9/5+32)+"°F":Math.round(weatherData.current.temperature_2m)+"°C"):(_useF?"--°F":"--°C"); font.family: Theme.fontFamily; font.pixelSize: Math.round(Theme.fontSizeHeader*Theme.weatherHeaderScale*1.15*Theme.scale(Screen)*weatherRoot.wscale); font.bold: true; color: Theme.textOn(card.color); Layout.alignment: Qt.AlignVCenter; Component.onCompleted: weatherRoot.warnContrast(card.color,color,'weather.temp') }
                    ColumnLayout { spacing: 1; Layout.alignment: Qt.AlignVCenter
                        Text { text: city.length>18?city.slice(0,17)+"\u2026":city; font.family: Theme.fontFamily; font.pixelSize: Math.round(Theme.fontSizeSmall*Theme.scale(Screen)*weatherRoot.wscale); font.bold: true; color: Theme.textOn(card.color); elide: Text.ElideRight }
                        Text { text: weatherData&&weatherData.timezone_abbreviation?weatherData.timezone_abbreviation:""; font.family: Theme.fontFamily; font.pixelSize: Math.round(Theme.tooltipFontPx*Theme.tooltipSmallScaleRatio*Theme.scale(Screen)*weatherRoot.wscale); color: Theme.textSecondary; visible: text!=="" } }
                }
            }

            // ── Details card (wind/humidity/moon) ──
            Item {
                Layout.fillWidth: true
                visible: weatherData&&weatherData.current
                implicitWidth: detailsRow.implicitWidth + 2 * contentLayout.cardPad
                implicitHeight: detailsRow.implicitHeight + 2 * contentLayout.cardPad
                Rectangle {
                    anchors.fill: parent
                    color: weatherRoot.cardBg
                    radius: contentLayout.cardRadius
                    z: 0
                }
                RowLayout {
                    id: detailsRow
                    anchors.fill: parent
                    anchors.margins: contentLayout.cardPad
                    spacing: Math.round(Theme.sidePanelSpacing*2.0*Theme.scale(Screen)*weatherRoot.wscale)
                    z: 1
                    RowLayout { spacing: Math.round(Theme.sidePanelSpacing * Theme.scale(Screen) * weatherRoot.wscale); visible: weatherRoot._cur&&typeof weatherRoot._cur.wind_speed_10m==='number'&&weatherRoot._cur.wind_speed_10m>0.1
                        MaterialIcon { icon: "navigation"; rotationAngle: WeatherIcons.windRotation(weatherRoot._cur?weatherRoot._cur.wind_direction_10m:0); size: Math.round(Theme.fontSizeSmall*0.85*Theme.scale(Screen)*weatherRoot.wscale); color: Theme.textOn(card.color) }
                        Text { text: weatherRoot._cur?WeatherIcons.formatWindFull(weatherRoot._cur.wind_speed_10m,weatherRoot._cur.wind_direction_10m):""; font.family: Theme.fontFamily; font.pixelSize: Math.round(Theme.fontSizeSmall*0.85*Theme.scale(Screen)*weatherRoot.wscale); color: Theme.textOn(card.color) } }
                    RowLayout { spacing: Math.round(Theme.sidePanelSpacing * Theme.scale(Screen) * weatherRoot.wscale); visible: weatherRoot._cur&&typeof weatherRoot._cur.relative_humidity_2m==='number'
                        MaterialIcon { icon: "water_drop"; size: Math.round(Theme.fontSizeSmall*0.85*Theme.scale(Screen)*weatherRoot.wscale); color: Theme.textOn(card.color) }
                        Text { text: weatherRoot._cur?Math.round(weatherRoot._cur.relative_humidity_2m)+"%":""; font.family: Theme.fontFamily; font.pixelSize: Math.round(Theme.fontSizeSmall*0.85*Theme.scale(Screen)*weatherRoot.wscale); color: Theme.textOn(card.color) } }
                    RowLayout { spacing: Math.round(Theme.sidePanelSpacing * Theme.scale(Screen) * weatherRoot.wscale)
                        MoonPhaseIcon { size: Math.round(Theme.fontSizeSmall*0.85*Theme.scale(Screen)*weatherRoot.wscale); moonColor: Theme.textOn(card.color); rimColor: Color.withAlpha(Theme.textOn(card.color),0.5) }
                        Text { text: WeatherIcons.moonName(new Date()); font.family: Theme.fontFamily; font.pixelSize: Math.round(Theme.fontSizeSmall*0.85*Theme.scale(Screen)*weatherRoot.wscale); color: Theme.textOn(card.color) }
                        Text { text: Math.round(WeatherIcons.moonIllumination(new Date()))+"%"; font.family: Theme.fontFamily; font.pixelSize: Math.round(Theme.fontSizeSmall*0.7*Theme.scale(Screen)*weatherRoot.wscale); color: Theme.textSecondary } }
                }
            }

            // ── Forecast card ──
            Item {
                Layout.fillWidth: true
                visible: weatherData&&weatherData.daily&&weatherData.daily.time
                implicitWidth: forecastRow.implicitWidth + 2 * contentLayout.cardPad
                implicitHeight: forecastRow.implicitHeight + 2 * contentLayout.cardPad
                Rectangle {
                    anchors.fill: parent
                    color: weatherRoot.cardBg
                    radius: contentLayout.cardRadius
                    z: 0
                }
                RowLayout {
                    id: forecastRow
                    anchors.fill: parent
                    anchors.margins: contentLayout.cardPad
                    spacing: Math.round(Theme.sidePanelSpacing*2.0*Theme.scale(Screen)*weatherRoot.wscale)
                    z: 1
                    Repeater { model: weatherData&&weatherData.daily&&weatherData.daily.time?Math.min(5,weatherData.daily.time.length):0
                        delegate: ColumnLayout { spacing: Math.round(Theme.sidePanelSpacingSmall * Theme.scale(Screen) * weatherRoot.wscale); Layout.alignment: Qt.AlignHCenter
                            Text { text: { try { var d=new Date(weatherData.daily.time[index]); var days=["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]; return days[d.getDay()] } catch(e) { return "" } } font.family: Theme.fontFamily; font.pixelSize: Math.round(Theme.fontSizeCaption*Theme.scale(Screen)*weatherRoot.wscale); color: Theme.textSecondary; horizontalAlignment: Text.AlignHCenter; Layout.alignment: Qt.AlignHCenter }
                            MaterialIcon { icon: WeatherIcons.materialSymbolForCode((weatherData.daily.weather_code||[])[index]!==undefined?(weatherData.daily.weather_code||[])[index]:-1); size: Math.round(Theme.panelPillIconSize*0.9*Theme.scale(Screen)*weatherRoot.wscale); color: Theme.textOn(card.color); Layout.alignment: Qt.AlignHCenter }
                            Text { text: { try { var hi=weatherData.daily.temperature_2m_max[index]; var lo=weatherData.daily.temperature_2m_min[index]; return _useF?Math.round(hi*9/5+32)+"°":Math.round(hi)+"°" } catch(e) { return "--" } } font.family: Theme.fontFamily; font.pixelSize: Math.round(Theme.fontSizeCaption*Theme.scale(Screen)*weatherRoot.wscale); color: Theme.textOn(card.color); horizontalAlignment: Text.AlignHCenter; Layout.alignment: Qt.AlignHCenter }
                            Text { text: { try { var lo=weatherData.daily.temperature_2m_min[index]; return _useF?Math.round(lo*9/5+32)+"°":Math.round(lo)+"°" } catch(e) { return "" } } font.family: Theme.fontFamily; font.pixelSize: Math.round(Theme.tooltipFontPx*0.71*Theme.scale(Screen)*weatherRoot.wscale); color: Theme.textSecondary; horizontalAlignment: Text.AlignHCenter; Layout.alignment: Qt.AlignHCenter } } }
                }
            }
        }
    }
}
