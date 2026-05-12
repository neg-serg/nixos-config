{
  lib,
  config,
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
      ''
      + lib.optionalString (config.features.media.aiUpscale.enable or false) ''
        # AI Upscale Bindings
        Alt+I vf toggle vapoursynth=~~/vs/ai/realesrgan.vpy:buffered-frames=3:concurrent-frames=1
        Alt+U run "/bin/sh" "-c" "~/.local/bin/ai-upscale-video \"$path\""
      '';
    }
  );
}
