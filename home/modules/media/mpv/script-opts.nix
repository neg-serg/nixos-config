{
  config,
  lib,
  ...
}:
lib.mkIf (config.features.gui.enable or false) {
  programs.mpv.scriptOpts = {
    osc = {
      deadzonesize = 0;
      scalewindowed = 0.666;
      scalefullscreen = 0.666;
      boxalpha = 140;
    };
    uosc = {
      timeline_line_width = 4;
      timeline_size = 30;
      timeline_persistency = "paused";
      controls = "menu,gap,subtitles,<has_many_audio>audio,<has_many_video>video,<has_many_edition>editions,<stream>stream-quality,gap,space,speed,space,shuffle,loop-playlist,loop-file,gap,prev,items,next,gap,fullscreen";
      color = lib.mkForce "foreground=005faf,foreground_text=000000,background=000000,background_text=6d839e";
      opacity = "volume=0.9,speed=0.6,menu=1,menu_parent=0.4,top_bar_title=0.8,window_border=0.8,curtain=0.5,timeline=0.9,timeline_chapters=0.7";
      top_bar_controls = "no";
      top_bar_title = "no";
      top_bar_flash_on = "video";
      scale = 1.1;
      scale_fullscreen = 1.1;
      font_scale = 1.1;
      flash_duration = 2000;
      autohide = "yes";
      stream_quality_options = "4320,2160,1440,1080,720,480";
      audio_types = "aac,ac3,aiff,ape,au,dsf,dts,flac,m4a,mid,midi,mka,mp3,mp4a,oga,ogg,opus,spx,tak,tta,wav,weba,wma,wv";
      subtitle_types = "aqt,ass,gsub,idx,jss,lrc,mks,pgs,pjs,psb,rt,slt,smi,sub,sup,srt,ssa,ssf,ttxt,txt,usf,vt,vtt";
    };
  };
}
