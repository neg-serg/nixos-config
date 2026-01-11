{
  config,
  lib,
  neg,
  impurity ? null,
  ...
}:
let
  n = neg impurity;
in
{
  config = lib.mkIf (config.features.gui.enable or false) (
    n.mkHomeFiles {
      # Profiles are split into a separate file and included in the main config
      ".config/mpv/profiles.conf".text = ''
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
    }
  );
}
