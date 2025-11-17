{
  config,
  lib,
  ...
}:
lib.mkIf (config.features.gui.enable or false) {
  programs.mpv.profiles = {
    "extension.ape" = {
      term-osd-bar-chars = "──╼ ·";
      term-osd-bar = true;
    };
    "extension.alac" = {
      term-osd-bar-chars = "──╼ ·";
      term-osd-bar = true;
    };
    "extension.flac" = {
      term-osd-bar-chars = "──╼ ·";
      term-osd-bar = true;
    };
    "extension.mp3" = {
      term-osd-bar-chars = "──╼ ·";
      term-osd-bar = true;
    };
    "extension.wav" = {
      term-osd-bar-chars = "──╼ ·";
      term-osd-bar = true;
    };
    "extension.gif" = {
      loop-file = true;
      osc = "no";
    };
    "protocol.http" = {
      cache-pause = false;
      cache = true;
    };
    "protocol.https" = {profile = "protocol.http";};
    "protocol.ytdl" = {profile = "protocol.http";};

    "4k60" = {
      profile-desc = "4k60";
      profile-cond = ''((width ==3840 and height ==2160) and p["estimated-vf-fps"]>=31)'';
      deband = false;
      interpolation = false;
    };

    "4k30" = {
      profile-desc = "4k30";
      profile-cond = ''((width ==3840 and height ==2160) and p["estimated-vf-fps"]<31)'';
      deband = false;
    };

    "full-hd60" = {
      profile-desc = "full-hd60";
      profile-cond = ''((width ==1920 and height ==1080) and not p["video-frame-info/interlaced"] and p["estimated-vf-fps"]>=31)'';
      interpolation = false;
    };

    "full-hd30" = {
      profile-desc = "full-hd30";
      profile-cond = ''((width ==1920 and height ==1080) and not p["video-frame-info/interlaced"] and p["estimated-vf-fps"]<31)'';
      interpolation = false;
    };
  };
}
