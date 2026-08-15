{
  lib,
  config,
  neg,
  ...
}:
{
  config = lib.mkIf (config.lib.neg.enabled "gui") (
    neg.mkHomeFiles {
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

        Alt+0 apply-profile ai-off
        Alt+1 apply-profile ai-fsrcnnx
        Alt+2 apply-profile ai-anime4k
        Alt+I vf toggle vapoursynth=~~/vs/ai/realesrgan.vpy:buffered-frames=3:concurrent-frames=1
        Alt+U run "/bin/sh" "-c" "~/.local/bin/ai-upscale-video \"$path\""

        # --- Russian layout duplicates (ЙЦУКЕН) ------------------------------------
        # mpv matches keys by the text the active layout produces, so latin-letter
        # binds break under the ru layout. These are the Cyrillic equivalents.
        # Reference table: docs/howto/hotkeys-ru-layout.ru.md
        з cycle pause; script-binding uosc/flash-pause-indicator           # p
        ш script-message-to uosc flash-top-bar                             # i
        к add sub-pos -1                                                   # r
        е add sub-pos +1                                                   # t
        м cycle sub-visibility 1                                           # v
        А cycle fullscreen 1                                               # F
        д seek +5; script-binding uosc/flash-timeline                      # l
        р seek -5; script-binding uosc/flash-timeline                      # h
        Д seek +60; script-binding uosc/flash-timeline                     # L
        Р seek -60; script-binding uosc/flash-timeline                     # H
        ь no-osd cycle mute; script-binding uosc/flash-volume              # m
        Ф cycle audio 1                                                    # A
        К cycle_values window-scale 2 0.5 1                                # R
        о cycle sub                                                        # j
        ы cycle sub                                                        # s
        Ctrl+р multiply speed 1/1.1                                        # Ctrl+h
        Ctrl+д multiply speed 1.1                                          # Ctrl+l
        Ctrl+Р set speed 1.0                                               # Ctrl+H
        Alt+ш vf toggle vapoursynth=~~/vs/ai/realesrgan.vpy:buffered-frames=3:concurrent-frames=1   # Alt+I
        Alt+г run "/bin/sh" "-c" "~/.local/bin/ai-upscale-video \"$path\""                          # Alt+U
        # `>`/`<` (uosc next/prev) do not exist in the ru layout — left unbound there.
      '';
    }
  );
}
