# Pure assertions over the kitty configs — eval-only, no derivations.
# Wired into flake/checks.nix as the "kitty-config" check. Keep this file free
# of config/flake dependencies: it is evaluated on every `nix flake check`.
#
# kitty has no inline comments: its parser splits a `map` line into the key and
# the rest, and the rest is the action's argument string (conf/utils.py —
# key_pat, val.split(maxsplit=1)). A trailing `# n→т` after `new_tab` therefore
# ran the command "#" (the tab died with *Failed to launch child: #*), and after
# `kitty_scrollback_nvim`/`neghints` it was passed to the kitten. Action lines
# must keep their comments on their own lines.
# See docs/howto/hotkeys-ru-layout.md, "Inline comments are arguments".
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
  commentPat = "[[:space:]]*#.*";

  offenders = lib.flatten (
    map (
      f:
      lib.imap1 (
        n: line:
        lib.optional (
          builtins.match actionPat line != null
          && builtins.match commentPat line == null
          && builtins.match ".*#.*" line != null
        ) "${builtins.baseNameOf f}:${toString n}: ${line}"
      ) (lib.splitString "\n" (builtins.readFile f))
    ) files
  );

  check = ok: msg: { inherit ok msg; };

  checks = [
    (check (offenders == [ ])
      "kitty action lines must carry no inline comments (kitty passes everything after the action to it as arguments; put the comment on its own line): ${lib.concatStringsSep "; " offenders}"
    )
  ];
in
{
  inherit checks;
  failures = builtins.filter (c: !c.ok) checks;
  report = builtins.concatStringsSep "; " (map (f: f.msg) (builtins.filter (c: !c.ok) checks));
}
