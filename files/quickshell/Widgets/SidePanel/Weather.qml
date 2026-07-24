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

        Canvas { id: moonTex; width: 256; height: 256; visible: false; property real _cachedPhase: -1; property bool _ready: false }
        Canvas {
            id: weatherDecor
            anchors.fill: parent; z: 0
            property int wcode: weatherRoot._wcode
            onWcodeChanged: requestPaint()

            onPaint: {
                var ctx=getContext("2d");ctx.reset();ctx.globalAlpha=0.12
                var w=width,h=height
                if(wcode>=1&&wcode<=3)drawClouds(ctx,w,h)
                else if(wcode>=45&&wcode<=48)drawFog(ctx,w,h)
                else if(wcode>=51&&wcode<=67||wcode>=80&&wcode<=82)drawRain(ctx,w,h)
                else if(wcode>=71&&wcode<=77)drawSnow(ctx,w,h)
                else if(wcode>=95&&wcode<=99){drawRain(ctx,w,h);drawStormBolt(ctx,w,h)}
                drawSunRays(ctx,w,h)
                drawMoon(ctx,w,h)
            }
            Timer { interval: 33; repeat: true; running: true; onTriggered: weatherDecor.requestPaint() }

            function drawSunRays(ctx,w,h){var cx=w*0.7,cy=h*0.3,r=Math.min(w,h)*0.1;var t=Date.now()*0.001;ctx.globalCompositeOperation="lighter";for(var i=0;i<720;i++){var a=Math.PI*2*i/720;var len=r*(1.2+Math.abs(Math.sin(i*4.7+t))*0.8+Math.abs(Math.sin(i*13-t*0.7))*0.4);var al=0.25+Math.abs(Math.sin(i*7+t*1.3))*0.45+Math.abs(Math.sin(i*19-t*0.4))*0.3;ctx.globalAlpha=al*0.35;ctx.strokeStyle=Theme.accentPrimary;ctx.lineWidth=1+Math.abs(Math.sin(i*23.7+t*3.1))*1.5;ctx.beginPath();ctx.moveTo(cx+Math.cos(a)*r*0.65,cy+Math.sin(a)*r*0.65);ctx.lineTo(cx+Math.cos(a)*len,cy+Math.sin(a)*len);ctx.stroke()}ctx.globalAlpha=0.92;ctx.fillStyle=Color.withAlpha("#ffffff",0.95);ctx.beginPath();ctx.arc(cx,cy,r*0.3,0,Math.PI*2);ctx.fill();var grd=ctx.createRadialGradient(cx,cy,r*0.15,cx,cy,r*1.15);grd.addColorStop(0,Color.withAlpha(Theme.accentPrimary,0.9));grd.addColorStop(0.25,Color.withAlpha(Theme.accentPrimary,0.55));grd.addColorStop(0.55,Color.withAlpha(Theme.accentPrimary,0.15));grd.addColorStop(1,"transparent");ctx.globalAlpha=0.65;ctx.fillStyle=grd;ctx.beginPath();ctx.arc(cx,cy,r*1.15,0,Math.PI*2);ctx.fill();ctx.globalCompositeOperation="source-over"}

            function hash(x,y){var n=Math.sin(x*127.1+y*311.7)*43758.5453;return n-Math.floor(n)}
            function fbm(x,y,oct){var v=0, a=0.5, f=1; for(var i=0;i<oct;i++){var ix=Math.floor(x*f),iy=Math.floor(y*f);var fx=x*f-ix,fy=y*f-iy;fx=fx*fx*(3-2*fx);fy=fy*fy*(3-2*fy);v+=a*((hash(ix,iy)*(1-fx)+hash(ix+1,iy)*fx)*(1-fy)+(hash(ix,iy+1)*(1-fx)+hash(ix+1,iy+1)*fx)*fy);a*=0.5;f*=2}return v}
            function genMoonTex(){var c=moonTex;var ctx=c.getContext("2d");var s=256;var img=ctx.createImageData(s,s);var d=img.data;for(var y=0;y<s;y++){for(var x=0;x<s;x++){var dx=x-s/2,dy=y-s/2;var dist=Math.sqrt(dx*dx+dy*dy)/128;if(dist>1){d[(y*s+x)*4+3]=0;continue}var base=0.55+fbm(x/128,y/128,6)*0.25-fbm(x/64+3,y/64+3,4)*0.15;var limb=1-Math.pow(dist,2.5)*0.3;base*=limb;var r=Math.floor(base*210+30);var g=Math.floor(base*200+28);var b=Math.floor(base*185+25);d[(y*s+x)*4]=Math.min(255,r);d[(y*s+x)*4+1]=Math.min(255,g);d[(y*s+x)*4+2]=Math.min(255,b);d[(y*s+x)*4+3]=255}}ctx.putImageData(img,0,0);for(var i=0;i<220;i++){var a=i*1.417;var cd=0.05+Math.abs(Math.sin(i*23.7))*0.9;var cx=128+Math.cos(a)*cd*120;var cy=128+Math.sin(a)*cd*120;var cr=1+Math.abs(Math.sin(i*7.13))*Math.abs(Math.sin(i*13.7))*14+Math.abs(Math.sin(i*31))*3;ctx.beginPath();ctx.arc(cx,cy,cr,0,Math.PI*2);var g=ctx.createRadialGradient(cx-cr*0.3,cy-cr*0.3,cr*0.1,cx,cy,cr);g.addColorStop(0,"rgba(0,0,0,0.35)");g.addColorStop(0.5,"rgba(0,0,0,0.08)");g.addColorStop(0.85,"rgba(255,255,255,0.12)");g.addColorStop(1,"rgba(255,255,255,0.04)");ctx.fillStyle=g;ctx.globalAlpha=0.9;ctx.fill();ctx.strokeStyle="rgba(255,255,255,0.08)";ctx.lineWidth=0.5;ctx.globalAlpha=0.6;ctx.stroke()}ctx.globalAlpha=1;moonTex._cachedPhase=WeatherIcons.moonAge(new Date());moonTex._ready=true}
            function drawMoon(ctx,w,h){var age=WeatherIcons.moonAge(new Date());if(!moonTex._ready||Math.abs(age-moonTex._cachedPhase)>0.02)genMoonTex();var cx=w*0.78,cy=h*0.72,d=Math.min(w,h)*0.26;ctx.save();ctx.beginPath();ctx.arc(cx,cy,d/2,0,Math.PI*2);ctx.clip();ctx.drawImage(moonTex,cx-d/2,cy-d/2,d,d);ctx.restore();ctx.globalCompositeOperation="source-over";ctx.globalAlpha=0.1;for(var i=0;i<80;i++){var a=i*0.82346;var dist=d/2*(1.1+Math.abs(Math.sin(i*17.3))*0.7);var sz=1+Math.abs(Math.sin(i*31.7))*2;ctx.fillStyle=Theme.accentPrimary;ctx.beginPath();ctx.arc(cx+Math.cos(a)*dist,cy+Math.sin(a)*dist,sz,0,Math.PI*2);ctx.fill()}var sa=age*Math.PI*2;var sx=cx+Math.cos(sa)*d/2*1.02;var sg=ctx.createRadialGradient(sx,cy,d*0.02,sx,cy,d*0.55);sg.addColorStop(0,Color.withAlpha("#000000",0.94));sg.addColorStop(0.55,Color.withAlpha("#000000",0.35));sg.addColorStop(1,"transparent");ctx.globalAlpha=1;ctx.fillStyle=sg;ctx.beginPath();ctx.arc(sx,cy,d*0.55,0,Math.PI*2);ctx.fill();ctx.globalAlpha=0.3;ctx.strokeStyle=Color.withAlpha(Theme.accentPrimary,0.5);ctx.lineWidth=0.5;ctx.beginPath();ctx.arc(cx,cy,d/2,0,Math.PI*2);ctx.stroke()}

            function drawClouds(ctx,w,h){ctx.fillStyle="#AABBCC";drawCloud(ctx,w*0.65,h*0.18,40);drawCloud(ctx,w*0.78,h*0.12,35);drawCloud(ctx,w*0.55,h*0.22,30)}
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
                MaterialIcon { id: weatherIcon; visible: !isLoading; icon: weatherRoot._wicon; size: Math.round(Theme.uiIconSizeLarge * 1.1 * Theme.scale(Screen) * weatherRoot.wscale); color: Theme.accentPrimary; Layout.alignment: Qt.AlignVCenter }
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

            RowLayout { spacing: Math.round(Theme.sidePanelSpacing*Theme.scale(Screen)*weatherRoot.wscale); Layout.fillWidth: true; Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 2; visible: weatherData&&weatherData.daily&&weatherData.daily.time
                Repeater { model: weatherData&&weatherData.daily&&weatherData.daily.time?Math.min(5,weatherData.daily.time.length):0
                    delegate: ColumnLayout { spacing: 1; Layout.alignment: Qt.AlignHCenter
                        Text { text: { try { var d=new Date(weatherData.daily.time[index]); var days=["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]; return days[d.getDay()] } catch(e) { return "" } } font.family: Theme.fontFamily; font.pixelSize: Math.round(Theme.fontSizeCaption*Theme.scale(Screen)*weatherRoot.wscale); color: Theme.textSecondary; horizontalAlignment: Text.AlignHCenter; Layout.alignment: Qt.AlignHCenter }
                        MaterialIcon { icon: WeatherIcons.materialSymbolForCode((weatherData.daily.weather_code||[])[index]!==undefined?(weatherData.daily.weather_code||[])[index]:-1); size: Math.round(Theme.panelPillIconSize*0.9*Theme.scale(Screen)*weatherRoot.wscale); color: Theme.textOn(card.color); Layout.alignment: Qt.AlignHCenter }
                        Text { text: { try { var hi=weatherData.daily.temperature_2m_max[index]; var lo=weatherData.daily.temperature_2m_min[index]; return _useF?Math.round(hi*9/5+32)+"°":Math.round(hi)+"°" } catch(e) { return "--" } } font.family: Theme.fontFamily; font.pixelSize: Math.round(Theme.fontSizeCaption*Theme.scale(Screen)*weatherRoot.wscale); color: Theme.textOn(card.color); horizontalAlignment: Text.AlignHCenter; Layout.alignment: Qt.AlignHCenter }
                        Text { text: { try { var lo=weatherData.daily.temperature_2m_min[index]; return _useF?Math.round(lo*9/5+32)+"°":Math.round(lo)+"°" } catch(e) { return "" } } font.family: Theme.fontFamily; font.pixelSize: Math.round(Theme.tooltipFontPx*0.71*Theme.scale(Screen)*weatherRoot.wscale); color: Theme.textSecondary; horizontalAlignment: Text.AlignHCenter; Layout.alignment: Qt.AlignHCenter } } } }
        }
    }
}
