{
  config,
  lib,
  neg,
  ...
}: {
  config = lib.mkIf (config.features.gui.enable or false) (
    neg.mkHomeFiles {
      ".config/mpv/profiles.conf".text = ''
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

        [hdr]
        profile-desc=Auto-HDR
        profile-cond=(p["video-params/gamma"] == "pq" or p["video-params/gamma"] == "hlg") and p["video-params/primaries"] == "bt.2020"
        target-colorspace-hint=yes
        hdr-compute-peak=yes
        tone-mapping=bt.2390
        tone-mapping-param=auto
        gamut-mapping-mode=relative
        target-peak=auto
      '';
    }
  );
}
