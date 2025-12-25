{
  lib,
  config,
  neg,
  impurity ? null,
  ...
}: let
  n = neg impurity;
in {
  config = lib.mkIf (config.features.gui.enable or false) (lib.mkMerge [
    {
      environment.variables.MPV_HOME = "${config.users.users.neg.home}/.config/mpv";
    }
    (n.mkHomeFiles {
      ".config/mpv/mpv.conf".text = ''
        input-ipc-server=${config.users.users.neg.home}/.config/mpv/socket
        cache=no
        gpu-shader-cache-dir=${config.users.users.neg.home}/.config/mpv/
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

        # Include profiles split into profiles.conf
        include=~~/profiles.conf
      '';
      ".config/mpv/styles.ass".text = ''
        ##[V4+ Styles]
        Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
        Style: Default,Lucida Grande,20,&H00FFFFFF,&HF0000000,&H80000000,&HF0000000,0,0,0,0,100,100,0,0.00,1,2,0,2,30,30,20,1
      '';
    })
  ]);
}
