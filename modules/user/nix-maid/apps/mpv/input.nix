{
  lib,
  config,
  neg,
  ...
}:
let
  # ЙЦУКЕН table + generators (lib/ru-keys.nix via specialArgs.neg) — the only
  # source for Russian-layout duplicate binds in this file.
  ruKeys = neg.ruKeys;

  # Russian-layout duplicates for the latin binds above. Each entry mirrors a
  # latin bind; the generator derives the Cyrillic key, so typos are impossible.
  # `>`/`<` (uosc next/prev) do not exist in the ru layout — intentionally absent.
  mpvRuBinds = [
    {
      key = "p";
      command = "cycle pause; script-binding uosc/flash-pause-indicator";
    }
    {
      key = "i";
      command = "script-message-to uosc flash-top-bar";
    }
    {
      key = "r";
      command = "add sub-pos -1";
    }
    {
      key = "t";
      command = "add sub-pos +1";
    }
    {
      key = "v";
      command = "cycle sub-visibility 1";
    }
    {
      key = "F";
      command = "cycle fullscreen 1";
    }
    {
      key = "l";
      command = "seek +5; script-binding uosc/flash-timeline";
    }
    {
      key = "h";
      command = "seek -5; script-binding uosc/flash-timeline";
    }
    {
      key = "L";
      command = "seek +60; script-binding uosc/flash-timeline";
    }
    {
      key = "H";
      command = "seek -60; script-binding uosc/flash-timeline";
    }
    {
      key = "m";
      command = "no-osd cycle mute; script-binding uosc/flash-volume";
    }
    {
      key = "A";
      command = "cycle audio 1";
    }
    {
      key = "R";
      command = "cycle_values window-scale 2 0.5 1";
    }
    {
      key = "j";
      command = "cycle sub";
    }
    {
      key = "s";
      command = "cycle sub";
    }
    {
      key = "Ctrl+h";
      command = "multiply speed 1/1.1";
    }
    {
      key = "Ctrl+l";
      command = "multiply speed 1.1";
    }
    {
      key = "Ctrl+H";
      command = "set speed 1.0";
    }
    {
      key = "Alt+I";
      command = "vf toggle vapoursynth=~~/vs/ai/realesrgan.vpy:buffered-frames=3:concurrent-frames=1";
    }
    {
      key = "Alt+U";
      command = "run \"/bin/sh\" \"-c\" \"~/.local/bin/ai-upscale-video \\\"$path\\\"\"";
    }
    # Emacs-style seek/navigation (additive; vim h/l/L/H still work)
    {
      key = "Ctrl+b";
      command = "seek -5; script-binding uosc/flash-timeline";
    }
    {
      key = "Ctrl+f";
      command = "seek +5; script-binding uosc/flash-timeline";
    }
    {
      key = "Ctrl+n";
      command = "playlist_next; script-binding uosc/flash-timeline";
    }
    {
      key = "Ctrl+p";
      command = "playlist_prev; script-binding uosc/flash-timeline";
    }
    {
      key = "Ctrl+a";
      command = "seek 0 absolute; script-binding uosc/flash-timeline";
    }
    {
      key = "Ctrl+e";
      command = "seek 100 absolute-percent; script-binding uosc/flash-timeline";
    }
  ];

  # mpv key with a modifier prefix ("Ctrl+h") → the same physical key's Cyrillic
  # counterpart ("Ctrl+р").
  mpvRuKey =
    key:
    let
      parts = lib.splitString "+" key;
    in
    if builtins.length parts == 1 then
      ruKeys.toRu key
    else
      (lib.concatStringsSep "+" (lib.init parts)) + "+" + ruKeys.toRu (lib.last parts);

  mpvRuBlock = ''
    # --- Russian layout duplicates (ЙЦУКЕН) ------------------------------------
    # GENERATED from lib/ru-keys.nix — do not edit by hand. Bind data lives in
    # modules/user/nix-maid/apps/mpv/input.nix (mpvRuBinds).
    # mpv matches keys by the text the active layout produces, so latin-letter
    # binds break under the ru layout.
    # Table: docs/howto/hotkeys-ru-layout.ru.md
  ''
  + lib.concatStringsSep "\n" (map (d: "${mpvRuKey d.key} ${d.command}  # ${d.key}") mpvRuBinds)
  + ''
    # `>`/`<` (uosc next/prev) do not exist in the ru layout — left unbound there.
  '';
in
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

        # Emacs-style seek/navigation (additive; vim h/l/L/H still work)
        Ctrl+b seek -5; script-binding uosc/flash-timeline
        Ctrl+f seek +5; script-binding uosc/flash-timeline
        Ctrl+n playlist_next; script-binding uosc/flash-timeline
        Ctrl+p playlist_prev; script-binding uosc/flash-timeline
        Ctrl+a seek 0 absolute; script-binding uosc/flash-timeline
        Ctrl+e seek 100 absolute-percent; script-binding uosc/flash-timeline

      ''
      + mpvRuBlock;
    }
  );
}
