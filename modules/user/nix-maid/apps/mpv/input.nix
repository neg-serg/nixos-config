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

  # Positional constructor for the table below: nixfmt keeps a two-name
  # `inherit` on one line, so each record costs one line instead of four.
  mpvRuBind = key: command: { inherit key command; };

  # Russian-layout duplicates for the latin binds above. Each entry mirrors a
  # latin bind; the generator derives the Cyrillic key, so typos are impossible.
  # `>`/`<` (uosc next/prev) — ru counterparts are Ю/Б (Shift+period/comma in ru).
  mpvRuBinds = [
    (mpvRuBind "p" "cycle pause; script-binding uosc/flash-pause-indicator")
    (mpvRuBind "i" "script-message-to uosc flash-top-bar")
    (mpvRuBind "r" "add sub-pos -1")
    (mpvRuBind "t" "add sub-pos +1")
    (mpvRuBind "v" "cycle sub-visibility 1")
    (mpvRuBind "F" "cycle fullscreen 1")
    (mpvRuBind "l" "seek +5; script-binding uosc/flash-timeline")
    (mpvRuBind "h" "seek -5; script-binding uosc/flash-timeline")
    (mpvRuBind "L" "seek +60; script-binding uosc/flash-timeline")
    (mpvRuBind "H" "seek -60; script-binding uosc/flash-timeline")
    (mpvRuBind "m" "no-osd cycle mute; script-binding uosc/flash-volume")
    (mpvRuBind "A" "cycle audio 1")
    (mpvRuBind "R" "cycle_values window-scale 2 0.5 1")
    (mpvRuBind "j" "cycle sub")
    (mpvRuBind "s" "cycle sub")
    (mpvRuBind "Ctrl+h" "multiply speed 1/1.1")
    (mpvRuBind "Ctrl+l" "multiply speed 1.1")
    (mpvRuBind "Ctrl+H" "set speed 1.0")
    (mpvRuBind "Alt+I" "vf toggle vapoursynth=~~/vs/ai/realesrgan.vpy:buffered-frames=3:concurrent-frames=1")
    (mpvRuBind "Alt+U" "run \"/bin/sh\" \"-c\" \"~/.local/bin/ai-upscale-video \\\"$path\\\"\"")
    # Emacs-style seek/navigation (additive; vim h/l/L/H still work)
    (mpvRuBind "Ctrl+b" "seek -5; script-binding uosc/flash-timeline")
    (mpvRuBind "Ctrl+f" "seek +5; script-binding uosc/flash-timeline")
    (mpvRuBind "Ctrl+n" "playlist_next; script-binding uosc/flash-timeline")
    (mpvRuBind "Ctrl+p" "playlist_prev; script-binding uosc/flash-timeline")
    (mpvRuBind "Ctrl+a" "seek 0 absolute; script-binding uosc/flash-timeline")
    (mpvRuBind "Ctrl+e" "seek 100 absolute-percent; script-binding uosc/flash-timeline")
    (mpvRuBind ">" "script-binding uosc/next; script-message-to uosc flash-elements top_bar,timeline")
    (mpvRuBind "<" "script-binding uosc/prev; script-message-to uosc flash-elements top_bar,timeline")
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
    # Table: docs/howto/hotkeys-ru-layout.md
  ''
  + lib.concatStringsSep "\n" (map (d: "${mpvRuKey d.key} ${d.command}  # ${d.key}") mpvRuBinds)
  + "\n";
in
{
  config = lib.mkIf (config.lib.neg.enabled "gui") (
    neg.mkHomeFiles {
      ".config/mpv/input.conf".text =
        builtins.readFile (config.lib.neg.path "files/mpv/input.conf") + mpvRuBlock;
    }
  );
}
