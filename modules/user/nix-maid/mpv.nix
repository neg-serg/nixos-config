{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.features.gui;

  # --- Scripts & Package ---
  scriptPkgs = with pkgs.mpvScripts; [
    cutter
    mpris
    quality-menu
    sponsorblock
    thumbfast
    uosc
  ];

  mpvPackage = pkgs.mpv.override {
    scripts = scriptPkgs;
    mpv = pkgs.mpv-unwrapped.override {
      vapoursynthSupport = true;
    };
  };

  # --- Shaders ---
  fsrcnnx = pkgs.fetchurl {
    url = "https://github.com/igv/FSRCNN-TensorFlow/releases/download/1.1/FSRCNNX_x2_8-0-4-1.glsl";
    sha256 = "1bn2ilzg007nxrbg4y81i3rgagsk4ivmjv11hb68alf9q72xn078";
  };
  krig = pkgs.fetchurl {
    url = "https://gist.githubusercontent.com/igv/a015fc885d5c22e6891820ad89555637/raw/KrigBilateral.glsl";
    sha256 = "1c0cjjysi9gmqy7nwj5ywc39hk6ivxfrhw8drrpn90vvnymrhiwa";
  };
  anime4k = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/bloc97/Anime4K/master/glsl/Upscale/Anime4K_Upscale_CNN_x2_S.glsl";
    sha256 = "19294sb65z6ssyvnhr2pcgb2c5j2f00nn9nbggpgf23r50pfqlsc";
  };
  ssim = pkgs.fetchurl {
    url = "https://gist.githubusercontent.com/igv/2364ffa6e81540f29cb7ab4c9bc05b6b/raw/SSimSuperRes.glsl";
    sha256 = "03s62mwcj90pnpp7dmwa4lbh404805g3f6s1a1908q0chhap3cm8";
  };
  # --- Config Generator Helper ---
in
  lib.mkIf (cfg.enable or false) {
    # 1. Install Package
    users.users.neg.packages = [mpvPackage];

    # 2. Configure Dotfiles via key-value to file
    users.users.neg.maid.file.home = {
      # Main Config
      ".config/mpv/mpv.conf".text = ''
        input-ipc-server=${config.home-manager.users.neg.xdg.configHome}/mpv/socket
        cache=no
        gpu-shader-cache-dir=${config.home-manager.users.neg.xdg.cacheHome}/mpv/
        hwdec=auto-safe
        profile=gpu-hq
        vd-lavc-dr=yes
        vd-lavc-threads=12
        vo=gpu-next
        gpu-context=wayland
        gpu-api=opengl
        deband-grain=48
        deband-iterations=4
        deband=yes
        video-sync=audio
        interpolation=no
        video-output-levels=full
        cscale=ewa_lanczossharp
        dscale=mitchell
        linear-downscaling=no
        scale=ewa_lanczos
        temporal-dither=no
        fbo-format=rgba16hf
        cscale-antiring=0.7
        dscale-antiring=0.7
        scale-antiring=0.7
        ao=pipewire,alsa,jack
        volume-max=100
        alang=en
        slang=ru,rus
        border=no
        fullscreen=yes
        geometry=100%:100%
        sub-auto=fuzzy
        sub-font="Helvetica Neue LT Std"
        sub-gauss=.82
        sub-gray=yes
        sub-scale=0.7
        cursor-autohide=500
        osc=no
        osd-bar-align-y=0
        osd-bar-h=3
        osd-bar=no
        osd-border-color='#cc000000'
        osd-border-size=1
        osd-color='#bb6d839e'
        osd-font=Iosevka
        osd-font-size=20
        osd-status-msg=''${time-pos} / ''${duration} (''${percent-pos}%)''${?estimated-vf-fps: FPS: ''${estimated-vf-fps}}
        ytdl-format=bestvideo+bestaudio/best
        screenshot-template=~/dw/scr-%F_%P
        msg-level=auto_profiles=warn

        # --- Profiles ---
        [extension.ape]
        term-osd-bar-chars=──╼ ·
        term-osd-bar=yes

        [extension.alac]
        term-osd-bar-chars=──╼ ·
        term-osd-bar=yes

        [extension.flac]
        term-osd-bar-chars=──╼ ·
        term-osd-bar=yes

        [extension.mp3]
        term-osd-bar-chars=──╼ ·
        term-osd-bar=yes

        [extension.wav]
        term-osd-bar-chars=──╼ ·
        term-osd-bar=yes

        [extension.gif]
        loop-file=yes
        osc=no

        [protocol.http]
        cache-pause=no
        cache=yes

        [protocol.https]
        profile=protocol.http

        [protocol.ytdl]
        profile=protocol.http

        [4k60]
        profile-desc=4k60
        profile-cond=((width ==3840 and height ==2160) and p["estimated-vf-fps"]>=31)
        deband=no
        interpolation=no

        [4k30]
        profile-desc=4k30
        profile-cond=((width ==3840 and height ==2160) and p["estimated-vf-fps"]<31)
        deband=no

        [full-hd60]
        profile-desc=full-hd60
        profile-cond=((width ==1920 and height ==1080) and not p["video-frame-info/interlaced"] and p["estimated-vf-fps"]>=31)
        interpolation=no

        [full-hd30]
        profile-desc=full-hd30
        profile-cond=((width ==1920 and height ==1080) and not p["video-frame-info/interlaced"] and p["estimated-vf-fps"]<31)
        interpolation=no

        # --- Shader Profiles ---
        [ai-off]
        glsl-shaders-clr

        [ai-fsrcnnx]
        glsl-shaders="~~/shaders/FSRCNNX_x2_8-0-4-1.glsl;~~/shaders/SSimSuperRes.glsl"
        cscale=ewa_lanczos

        [ai-anime4k]
        glsl-shaders="~~/shaders/Anime4K_Upscale_CNN_x2_S.glsl"
        cscale=ewa_lanczos
      '';

      # Input Bindings
      ".config/mpv/input.conf".text = ''
        + add panscan +0.1
        - add panscan -0.1
        tab script-binding uosc/toggle-ui
        space cycle pause; script-binding uosc/flash-pause-indicator
        p cycle pause; script-binding uosc/flash-pause-indicator
        ctrl+enter script-binding uosc/open-file
        i script-message-to uosc flash-top-bar
        Ctrl+h multiply speed 1/1.1
        Ctrl+l multiply speed 1.1
        Ctrl+H set speed 1.0
        r add sub-pos -1
        t add sub-pos +1
        v cycle sub-visibility 1
        F cycle fullscreen 1
        right seek +5; script-binding uosc/flash-timeline
        left seek -5; script-binding uosc/flash-timeline
        up seek +30; script-binding uosc/flash-timeline
        down seek -30; script-binding uosc/flash-timeline
        l seek +5; script-binding uosc/flash-timeline
        h seek -5; script-binding uosc/flash-timeline
        L seek +60; script-binding uosc/flash-timeline
        H seek -60; script-binding uosc/flash-timeline
        0 no-osd add volume +1; script-binding uosc/flash-volume
        9 no-osd add volume -1; script-binding uosc/flash-volume
        WHEEL_UP no-osd add volume +1; script-binding uosc/flash-volume
        WHEEL_DOWN no-osd add volume -1; script-binding uosc/flash-volume
        m no-osd cycle mute; script-binding uosc/flash-volume
        A cycle audio 1
        > script-binding uosc/next; script-message-to uosc flash-elements top_bar,timeline
        < script-binding uosc/prev; script-message-to uosc flash-elements top_bar,timeline
        ESC playlist_next
        R cycle_values window-scale 2 0.5 1
        j cycle sub
        s cycle sub
        mbtn_left cycle pause 1
        mbtn_right script-binding uosc/menu

        # Shader Bindings
        Alt+0 apply-profile ai-off
        Alt+1 apply-profile ai-fsrcnnx
        Alt+2 apply-profile ai-anime4k
      '';

      # Script Options
      ".config/mpv/script-opts/osc.conf".text = ''
        deadzonesize=0
        scalewindowed=0.666
        scalefullscreen=0.666
        boxalpha=140
      '';

      ".config/mpv/script-opts/uosc.conf".text = ''
        timeline_line_width=4
        timeline_size=30
        timeline_persistency=paused
        controls=menu,gap,subtitles,<has_many_audio>audio,<has_many_video>video,<has_many_edition>editions,<stream>stream-quality,gap,space,speed,space,shuffle,loop-playlist,loop-file,gap,prev,items,next,gap,fullscreen
        color=foreground=005faf,foreground_text=000000,background=000000,background_text=6d839e
        opacity=volume=0.9,speed=0.6,menu=1,menu_parent=0.4,top_bar_title=0.8,window_border=0.8,curtain=0.5,timeline=0.9,timeline_chapters=0.7
        top_bar_controls=no
        top_bar_title=no
        top_bar_flash_on=video
        scale=1.1
        scale_fullscreen=1.1
        font_scale=1.1
        flash_duration=2000
        autohide=yes
        stream_quality_options=4320,2160,1440,1080,720,480
        audio_types=aac,ac3,aiff,ape,au,dsf,dts,flac,m4a,mid,midi,mka,mp3,mp4a,oga,ogg,opus,spx,tak,tta,wav,weba,wma,wv
        subtitle_types=aqt,ass,gsub,idx,jss,lrc,mks,pgs,pjs,psb,rt,slt,smi,sub,sup,srt,ssa,ssf,ttxt,txt,usf,vt,vtt
      '';

      # Shaders
      ".config/mpv/shaders/FSRCNNX_x2_8-0-4-1.glsl".source = fsrcnnx;
      ".config/mpv/shaders/KrigBilateral.glsl".source = krig;
      ".config/mpv/shaders/Anime4K_Upscale_CNN_x2_S.glsl".source = anime4k;
      ".config/mpv/shaders/SSimSuperRes.glsl".source = ssim;

      ".config/mpv/styles.ass".text = ''
        ##[V4+ Styles]
        Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
        Style: Default,Lucida Grande,20,&H00FFFFFF,&HF0000000,&H80000000,&HF0000000,0,0,0,0,100,100,0,0.00,1,2,0,2,30,30,20,1
      '';
    };
  }
