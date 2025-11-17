{
  config,
  lib,
  ...
}:
lib.mkIf (config.features.gui.enable or false) {
  programs.mpv = {
    enable = true;
    config = {
      input-ipc-server = "${config.xdg.configHome}/mpv/socket";
      cache = "no";
      gpu-shader-cache-dir = "${config.xdg.cacheHome}/mpv/";
      hwdec = "auto-safe";
      profile = "gpu-hq";
      vd-lavc-dr = true;
      vd-lavc-threads = "12";
      vo = "gpu-next";
      gpu-context = "wayland";
      gpu-api = "opengl";
      deband-grain = 48;
      deband-iterations = 4;
      deband = true;
      video-sync = "audio";
      interpolation = false;
      video-output-levels = "full";
      cscale = "ewa_lanczossharp";
      dscale = "mitchell";
      linear-downscaling = false;
      scale = "ewa_lanczos";
      temporal-dither = "no";
      fbo-format = "rgba16hf";
      cscale-antiring = "0.7";
      dscale-antiring = "0.7";
      scale-antiring = "0.7";
      ao = "pipewire,alsa,jack";
      volume-max = "100";
      alang = "en";
      slang = "ru,rus";
      border = "no";
      fullscreen = "yes";
      geometry = "100%:100%";
      sub-auto = "fuzzy";
      sub-font = lib.mkForce ["Helvetica Neue LT Std" "HelveticaNeue LT CYR 57 Cond"];
      sub-gauss = ".82";
      sub-gray = "yes";
      sub-scale = "0.7";
      cursor-autohide = "500";
      osc = "no";
      osd-bar-align-y = "0";
      osd-bar-h = "3";
      osd-bar = "no";
      osd-border-color = lib.mkForce "#cc000000";
      osd-border-size = "1";
      osd-color = lib.mkForce "#bb6d839e";
      osd-font = lib.mkForce "Iosevka";
      osd-font-size = lib.mkForce "20";
      osd-status-msg = "$\\{time-pos\\} / $\\{duration\\} ($\\{percent-pos\\}%)$\\{?estimated-vf-fps: FPS: $\\{estimated-vf-fps\\}\\}";
      ytdl-format = "bestvideo+bestaudio/best";
      screenshot-template = "~/dw/scr-%F_%P";
    };
  };
}
