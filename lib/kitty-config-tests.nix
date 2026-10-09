# Pure assertions over the kitty configs — eval-only, no derivations.
# Wired into flake/checks.nix as the "kitty-config" check. Keep this file free
# of config/flake dependencies: it is evaluated on every `nix flake check`.
#
# Two invariants, both learned the hard way (docs/howto/hotkeys-ru-layout.md):
#
# 1. kitty has no inline comments: its parser splits a `map` line into the key
#    and the rest, and the rest is the action's argument string (conf/utils.py —
#    key_pat, val.split(maxsplit=1)). A trailing `# n→т` after `new_tab` ran the
#    command "#" (the tab died with *Failed to launch child: #*), and after
#    `kitty_scrollback_nvim`/`neghints` it was passed to the kitten.
#
# 2. Custom mappings default to the `shifted` fallback only, so a Latin bind
#    stops matching under a non-Latin layout unless the map carries
#    `--allow-fallback=shifted,ascii` (the pair kitty's own shortcuts use). The
#    ru layout is handled by that option — action lines must stay Latin, no
#    Cyrillic duplicates (checked: real keycodes under `us,ru`, both plain and
#    Shift-ed, match the Latin binds).
{
  lib,
}:
let
  # The two files that hold key bindings and action aliases. tab.conf/theme.conf
  # only carry values (colours use `#rrggbb`), so they are deliberately out.
  files = [
    ../files/kitty/key.conf
    ../files/kitty/mouse.conf
  ];

  # map / mouse_map / action_alias / kitten_alias: kitty takes everything after
  # the action name as its arguments.
  actionPat = "[[:space:]]*(map|mouse_map|action_alias|kitten_alias)[[:space:]].*";
  mapPat = "[[:space:]]*map[[:space:]].*";
  commentPat = "[[:space:]]*#.*";

  linesOf = f: lib.imap1 (n: line: { inherit n line; }) (lib.splitString "\n" (builtins.readFile f));

  # "file:line: text" for every line failing predicate `bad`.
  offenders =
    bad: kind:
    lib.flatten (
      map (
        f:
        map (x: "${builtins.baseNameOf f}:${toString x.n} (${kind}): ${x.line}") (
          builtins.filter (x: bad x.line) (linesOf f)
        )
      ) files
    );

  inlineComments = offenders (
    line:
    builtins.match actionPat line != null
    && builtins.match commentPat line == null
    && builtins.match ".*#.*" line != null
  ) "inline comment";

  missingFallback = offenders (
    line:
    builtins.match mapPat line != null
    && builtins.match commentPat line == null
    && !(builtins.match ".*--allow-fallback=(shifted,ascii|ascii,shifted).*" line != null)
  ) "map without --allow-fallback=shifted,ascii";

  # No Cyrillic (or any non-ASCII) key on an action line: under a non-Latin
  # layout the fallback does the matching, literals would only work for one
  # layout and break the shifted (uppercase) events.
  nonAsciiKeys = offenders (
    line: builtins.match actionPat line != null && builtins.match "[ -~]*" line == null
  ) "non-ASCII key";

  check = ok: msg: { inherit ok msg; };

  checks = [
    (check (inlineComments == [ ])
      "kitty action lines must carry no inline comments (kitty passes everything after the action to it as arguments; put the comment on its own line): ${lib.concatStringsSep "; " inlineComments}"
    )
    (check (missingFallback == [ ])
      "every kitty map must carry --allow-fallback=shifted,ascii, or the bind stops matching under a non-Latin layout: ${lib.concatStringsSep "; " missingFallback}"
    )
    (check (nonAsciiKeys == [ ])
      "kitty action lines must stay ASCII (the ru layout is handled by --allow-fallback, not by literal Cyrillic keys): ${lib.concatStringsSep "; " nonAsciiKeys}"
    )
  ];
in
{
  inherit checks;
  failures = builtins.filter (c: !c.ok) checks;
  report = builtins.concatStringsSep "; " (map (f: f.msg) (builtins.filter (c: !c.ok) checks));
}
