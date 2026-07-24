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

    function warnContrast(bg, fg, label) { try { if(!(Settings.settings&&Settings.settings.debugLogs))return;var r=Color.contrastRatio(bg,fg);var t=(Settings.settings&&Settings.settings.contrastWarnRatio)?Settings.settings.contrastWarnRatio:4.5;if(r<t)console.debug('[Contrast]',label||'text','ratio',r.toFixed(2)) } catch(e){console.warn("[Weather.warnContrast]",e)} }

    Rectangle {
        id: card
        anchors.fill: parent
        color: Color.withAlpha(Theme.surface, 0.85)
        border.color: "transparent"
        border.width: 0
        radius: Math.round(Theme.sidePanelCornerRadius * Theme.scale(Screen) * weatherRoot.wscale)
        clip: true

        Rectangle { anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; height: 1; color: Color.withAlpha(Theme.accentPrimary, 0.25); z: 2 }

        Image { id: moonImg; source: "../../illustrations/moon_nasa.jpg"; visible: false; cache: false }
        Canvas {
            id: weatherDecor
            anchors.fill: parent; z: 0
            property int wcode: weatherRoot._wcode
            onWcodeChanged: requestPaint()

            onPaint: {
                var ctx=getContext("2d");ctx.reset();ctx.globalAlpha=0.25
                var w=width,h=height
                drawSunRays(ctx,w,h)
                drawMoon(ctx,w,h)
                if(wcode>=1&&wcode<=3)drawClouds(ctx,w,h)
                else if(wcode>=45&&wcode<=48)drawFog(ctx,w,h)
                else if(wcode>=51&&wcode<=67||wcode>=80&&wcode<=82)drawRain(ctx,w,h)
                else if(wcode>=71&&wcode<=77)drawSnow(ctx,w,h)
                else if(wcode>=95&&wcode<=99){drawRain(ctx,w,h);drawStormBolt(ctx,w,h)}
            }
            Timer { interval: 33; repeat: true; running: true; onTriggered: weatherDecor.requestPaint() }

            function drawSunRays(ctx,w,h){var cx=w*0.7,cy=h*0.35,r=Math.min(w,h)*0.1;var t=Date.now()*0.001;var grd=ctx.createRadialGradient(cx,cy,r*0.05,cx,cy,r*2);grd.addColorStop(0,"rgba(255,255,220,0.25)");grd.addColorStop(0.15,"rgba(255,248,200,0.12)");grd.addColorStop(0.4,"rgba(255,220,150,0.04)");grd.addColorStop(1,"transparent");ctx.fillStyle=grd;ctx.beginPath();ctx.arc(cx,cy,r*2,0,Math.PI*2);ctx.fill();ctx.globalCompositeOperation="lighter";for(var i=0;i<1440;i++){var a=Math.PI*2*i/1440;var wig=Math.sin(i*4.7+t*0.8)*0.3+Math.sin(i*13.3-t*0.5)*0.18+Math.sin(i*21.1+t*1.1)*0.1;var len=r*(1.0+wig);var al=0.2+Math.abs(wig)*0.6;ctx.globalAlpha=al*0.28;ctx.strokeStyle=Theme.accentPrimary;ctx.lineWidth=0.6+Math.abs(Math.sin(i*23.7+t*3.1))*1.2;ctx.beginPath();ctx.moveTo(cx+Math.cos(a)*r*0.5,cy+Math.sin(a)*r*0.5);ctx.lineTo(cx+Math.cos(a)*len,cy+Math.sin(a)*len);ctx.stroke()}ctx.globalAlpha=0.8;var grd2=ctx.createRadialGradient(cx,cy,r*0.05,cx,cy,r*0.55);grd2.addColorStop(0,"rgba(255,255,255,1)");grd2.addColorStop(0.15,"rgba(255,255,240,0.9)");grd2.addColorStop(0.35,Color.withAlpha(Theme.accentPrimary,0.5));grd2.addColorStop(0.6,Color.withAlpha(Theme.accentPrimary,0.1));grd2.addColorStop(1,"transparent");ctx.fillStyle=grd2;ctx.beginPath();ctx.arc(cx,cy,r*0.55,0,Math.PI*2);ctx.fill();ctx.globalCompositeOperation="source-over"}
            function drawMoon(ctx,w,h){var age=WeatherIcons.moonAge(new Date());var cx=w*0.78,cy=h*0.72,d=Math.min(w,h)*0.26;ctx.save();ctx.beginPath();ctx.arc(cx,cy,d/2,0,Math.PI*2);ctx.clip();if(moonImg.status===Image.Ready){ctx.drawImage(moonImg,cx-d/2,cy-d/2,d,d)}else{var surf=ctx.createRadialGradient(cx-d*0.25,cy-d*0.25,d*0.02,cx,cy,d/2);surf.addColorStop(0,Color.withAlpha("#f0e8d8",0.95));surf.addColorStop(0.5,Color.withAlpha("#c8b898",0.85));surf.addColorStop(1,Color.withAlpha("#706050",0.6));ctx.fillStyle=surf;ctx.beginPath();ctx.arc(cx,cy,d/2,0,Math.PI*2);ctx.fill()}ctx.restore();var sa=age*Math.PI*2;var sx=cx+Math.cos(sa)*d/2*1.02;var sg=ctx.createRadialGradient(sx,cy,d*0.02,sx,cy,d*0.55);sg.addColorStop(0,Color.withAlpha("#000000",0.94));sg.addColorStop(0.55,Color.withAlpha("#000000",0.35));sg.addColorStop(1,"transparent");ctx.globalAlpha=1;ctx.fillStyle=sg;ctx.beginPath();ctx.arc(sx,cy,d*0.55,0,Math.PI*2);ctx.fill();ctx.globalAlpha=0.3;ctx.strokeStyle=Color.withAlpha(Theme.accentPrimary,0.5);ctx.lineWidth=0.5;ctx.beginPath();ctx.arc(cx,cy,d/2,0,Math.PI*2);ctx.stroke()}

            function drawClouds(ctx,w,h){ctx.fillStyle="rgba(170,187,204,0.85)";drawCloud(ctx,w*0.6,h*0.55,45);drawCloud(ctx,w*0.75,h*0.48,38);drawCloud(ctx,w*0.5,h*0.42,32)}
            function drawCloud(ctx,cx,cy,r){ctx.beginPath();ctx.arc(cx,cy,r,0,Math.PI*2);ctx.arc(cx+r*0.7,cy-r*0.25,r*0.75,0,Math.PI*2);ctx.arc(cx+r*1.2,cy,r*0.7,0,Math.PI*2);ctx.arc(cx-r*0.6,cy+r*0.1,r*0.6,0,Math.PI*2);ctx.arc(cx+r*0.5,cy-r*0.5,r*0.55,0,Math.PI*2);ctx.fill()}
            function drawFog(ctx,w,h){ctx.strokeStyle="#8899AA";ctx.lineWidth=2;for(var i=0;i<6;i++){var y=h*0.2+i*h*0.1;ctx.globalAlpha=0.04+i*0.006;ctx.beginPath();ctx.moveTo(w*0.1,y);ctx.lineTo(w*0.9,y);ctx.stroke()}ctx.globalAlpha=0.07}
            function drawRain(ctx,w,h){ctx.strokeStyle="#88AACC";ctx.lineWidth=1;for(var i=0;i<40;i++){var x=(i*37+13)%w;var y=(i*53+7)%h;ctx.beginPath();ctx.moveTo(x,y);ctx.lineTo(x-3,y+8);ctx.stroke()}}
            function drawSnow(ctx,w,h){ctx.fillStyle="#CCDDEE";for(var i=0;i<30;i++){var x=(i*47+13)%w;var y=(i*59+7)%h;var r2=1.5+(i%3)*1;ctx.beginPath();ctx.arc(x,y,r2,0,Math.PI*2);ctx.fill()}}
            function drawStormBolt(ctx,w,h){ctx.strokeStyle="#FFD040";ctx.lineWidth=2.5;ctx.beginPath();var bx=w*0.75,by=h*0.08;ctx.moveTo(bx,by);ctx.lineTo(bx-10,by+22);ctx.lineTo(bx+4,by+22);ctx.lineTo(bx-8,by+44);ctx.stroke()}
        }




        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Math.round(Theme.panelSideMargin * 0.9 * Theme.scale(Screen) * weatherRoot.wscale)
            spacing: Math.round(Theme.sidePanelSpacingSmall * Theme.scale(Screen) * weatherRoot.wscale)
            z: 2

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.round(Theme.uiIconSizeLarge * Theme.scale(Screen) * weatherRoot.wscale)
                spacing: Math.round(Theme.sidePanelSpacing * Theme.scale(Screen) * weatherRoot.wscale)
                Spinner { id: loadingSpinner; running: isLoading; color: Theme.accentPrimary; size: Math.round(Theme.uiIconSizeLarge * Theme.scale(Screen) * weatherRoot.wscale); visible: isLoading; Layout.alignment: Qt.AlignVCenter }
                Canvas { id: sunIcon; visible: !isLoading; width: Math.round(Theme.uiIconSizeLarge*1.5*Theme.scale(Screen)*weatherRoot.wscale); height: width; Layout.alignment: Qt.AlignVCenter; onPaint: {var ctx=getContext("2d");ctx.reset();var s=width,r=s*0.30;var cx=s/2,cy=s/2;var grd=ctx.createRadialGradient(cx,cy,r*0.08,cx,cy,r*1.4);grd.addColorStop(0,"rgba(255,255,255,1)");grd.addColorStop(0.15,"rgba(255,255,240,0.95)");grd.addColorStop(0.4,Color.withAlpha(Theme.accentPrimary,0.5));grd.addColorStop(0.7,Color.withAlpha(Theme.accentPrimary,0.1));grd.addColorStop(1,"transparent");ctx.fillStyle=grd;ctx.beginPath();ctx.arc(cx,cy,r*1.4,0,Math.PI*2);ctx.fill();ctx.globalCompositeOperation="lighter";for(var i=0;i<90;i++){var a=Math.PI*2*i/90;var len=r*(0.55+Math.abs(Math.sin(i*5.3))*0.55);ctx.globalAlpha=0.15+Math.abs(Math.sin(i*7.7))*0.2;ctx.strokeStyle=Theme.accentPrimary;ctx.lineWidth=0.5+Math.abs(Math.sin(i*19.3))*1.2;ctx.beginPath();ctx.moveTo(cx+Math.cos(a)*r*0.3,cy+Math.sin(a)*r*0.3);ctx.lineTo(cx+Math.cos(a)*len,cy+Math.sin(a)*len);ctx.stroke()}ctx.globalCompositeOperation="source-over"} Timer { interval: 50; repeat: true; running: true; onTriggered: sunIcon.requestPaint() } }
                Text { text: weatherData&&weatherData.current?(_useF?Math.round(weatherData.current.temperature_2m*9/5+32)+"°F":Math.round(weatherData.current.temperature_2m)+"°C"):(_useF?"--°F":"--°C"); font.family: Theme.fontFamily; font.pixelSize: Math.round(Theme.fontSizeHeader*Theme.weatherHeaderScale*1.15*Theme.scale(Screen)*weatherRoot.wscale); font.bold: true; color: Theme.textOn(card.color); Layout.alignment: Qt.AlignVCenter; Component.onCompleted: weatherRoot.warnContrast(card.color,color,'weather.temp') }
                ColumnLayout { spacing: 1; Layout.alignment: Qt.AlignVCenter
                    Text { text: city.length>18?city.slice(0,17)+"\u2026":city; font.family: Theme.fontFamily; font.pixelSize: Math.round(Theme.fontSizeSmall*Theme.scale(Screen)*weatherRoot.wscale); font.bold: true; color: Theme.textOn(card.color); elide: Text.ElideRight }
                    Text { text: weatherData&&weatherData.timezone_abbreviation?weatherData.timezone_abbreviation:""; font.family: Theme.fontFamily; font.pixelSize: Math.round(Theme.tooltipFontPx*Theme.tooltipSmallScaleRatio*Theme.scale(Screen)*weatherRoot.wscale); color: Theme.textSecondary; visible: text!=="" } }
                Item { Layout.fillWidth: true }
            }

            RowLayout { Layout.fillWidth: true; spacing: Math.round(Theme.sidePanelSpacing*Theme.scale(Screen)*weatherRoot.wscale); visible: weatherData&&weatherData.current
                RowLayout { spacing: 4; visible: weatherRoot._cur&&typeof weatherRoot._cur.wind_speed_10m==='number'&&weatherRoot._cur.wind_speed_10m>0.1
                    MaterialIcon { icon: "navigation"; rotationAngle: WeatherIcons.windRotation(weatherRoot._cur?weatherRoot._cur.wind_direction_10m:0); size: Math.round(Theme.fontSizeSmall*0.85*Theme.scale(Screen)*weatherRoot.wscale); color: Theme.textOn(card.color) }
                    Text { text: weatherRoot._cur?WeatherIcons.formatWindFull(weatherRoot._cur.wind_speed_10m,weatherRoot._cur.wind_direction_10m):""; font.family: Theme.fontFamily; font.pixelSize: Math.round(Theme.fontSizeSmall*0.85*Theme.scale(Screen)*weatherRoot.wscale); color: Theme.textOn(card.color) } }
                RowLayout { spacing: 4; visible: weatherRoot._cur&&typeof weatherRoot._cur.relative_humidity_2m==='number'
                    MaterialIcon { icon: "water_drop"; size: Math.round(Theme.fontSizeSmall*0.85*Theme.scale(Screen)*weatherRoot.wscale); color: Theme.textOn(card.color) }
                    Text { text: weatherRoot._cur?Math.round(weatherRoot._cur.relative_humidity_2m)+"%":""; font.family: Theme.fontFamily; font.pixelSize: Math.round(Theme.fontSizeSmall*0.85*Theme.scale(Screen)*weatherRoot.wscale); color: Theme.textOn(card.color) } }
                RowLayout { spacing: 4
                    MoonPhaseIcon { size: Math.round(Theme.fontSizeSmall*0.85*Theme.scale(Screen)*weatherRoot.wscale); moonColor: Theme.textOn(card.color); rimColor: Color.withAlpha(Theme.textOn(card.color),0.5) }
                    Text { text: WeatherIcons.moonName(new Date()); font.family: Theme.fontFamily; font.pixelSize: Math.round(Theme.fontSizeSmall*0.85*Theme.scale(Screen)*weatherRoot.wscale); color: Theme.textOn(card.color) }
                    Text { text: Math.round(WeatherIcons.moonIllumination(new Date()))+"%"; font.family: Theme.fontFamily; font.pixelSize: Math.round(Theme.fontSizeSmall*0.7*Theme.scale(Screen)*weatherRoot.wscale); color: Theme.textSecondary } }
                Item { Layout.fillWidth: true } }

            RowLayout { spacing: Math.round(Theme.sidePanelSpacing*Theme.scale(Screen)*weatherRoot.wscale); Layout.fillWidth: true; Layout.alignment: Qt.AlignLeft; Layout.topMargin: 2; visible: weatherData&&weatherData.daily&&weatherData.daily.time
                Repeater { model: weatherData&&weatherData.daily&&weatherData.daily.time?Math.min(5,weatherData.daily.time.length):0
                    delegate: ColumnLayout { spacing: 1; Layout.alignment: Qt.AlignLeft
                        Text { text: { try { var d=new Date(weatherData.daily.time[index]); var days=["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]; return days[d.getDay()] } catch(e) { return "" } } font.family: Theme.fontFamily; font.pixelSize: Math.round(Theme.fontSizeCaption*Theme.scale(Screen)*weatherRoot.wscale); color: Theme.textSecondary; horizontalAlignment: Text.AlignLeft; Layout.alignment: Qt.AlignLeft }
                        MaterialIcon { icon: WeatherIcons.materialSymbolForCode((weatherData.daily.weather_code||[])[index]!==undefined?(weatherData.daily.weather_code||[])[index]:-1); size: Math.round(Theme.panelPillIconSize*0.9*Theme.scale(Screen)*weatherRoot.wscale); color: Theme.textOn(card.color); Layout.alignment: Qt.AlignHCenter }
                        Text { text: { try { var hi=weatherData.daily.temperature_2m_max[index]; var lo=weatherData.daily.temperature_2m_min[index]; return _useF?Math.round(hi*9/5+32)+"°":Math.round(hi)+"°" } catch(e) { return "--" } } font.family: Theme.fontFamily; font.pixelSize: Math.round(Theme.fontSizeCaption*Theme.scale(Screen)*weatherRoot.wscale); color: Theme.textOn(card.color); horizontalAlignment: Text.AlignLeft; Layout.alignment: Qt.AlignLeft }
                        Text { text: { try { var lo=weatherData.daily.temperature_2m_min[index]; return _useF?Math.round(lo*9/5+32)+"°":Math.round(lo)+"°" } catch(e) { return "" } } font.family: Theme.fontFamily; font.pixelSize: Math.round(Theme.tooltipFontPx*0.71*Theme.scale(Screen)*weatherRoot.wscale); color: Theme.textSecondary; horizontalAlignment: Text.AlignLeft; Layout.alignment: Qt.AlignLeft } } } }
        }
    }
}
