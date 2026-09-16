# Structural home-file helpers — pure functions with no config dependency.
# Single source of truth: flake/nixos.nix (specialArgs.neg) and
# flake/checks.nix import this file instead of inlining or stubbing them.
rec {
  # Home files for the primary user, applied via nix-maid (users.users.neg.maid)
  mkHomeFiles = files: {
    users.users.neg.maid.file.home = files;
  };

  # Import modules from a directory — single replacement for the
  # `builtins.readDir ./. |> attrNames |> filter |> map` pipeline copied into
  # every auto-importing default.nix.
  #
  #   importDir { dir = ./.; }                      # flat *.nix files
  #   importDir { dir = ./.; includeDirs = true; }  # + module subdirectories
  #   importDir { dir = ./.; exclude = [ "x.nix" ]; }
  #
  # default.nix is always dropped (it is the importer itself). With
  # includeDirs, a subdirectory is imported only when it carries its own
  # default.nix — data directories (scripts/, mutt-conf/, asset bundles) are
  # skipped automatically instead of being listed in every caller's exclude.
  importDir =
    {
      dir,
      includeDirs ? false,
      exclude ? [ ],
    }:
    let
      entries = builtins.readDir dir;
      hasSuffix =
        suf: s:
        let
          sLen = builtins.stringLength s;
          sufLen = builtins.stringLength suf;
        in
        sLen >= sufLen && builtins.substring (sLen - sufLen) sufLen s == suf;
      isModuleDir =
        name: entries.${name} == "directory" && builtins.pathExists (dir + "/${name}/default.nix");
      isModuleFile = name: entries.${name} != "directory" && hasSuffix ".nix" name;
      keep =
        name:
        name != "default.nix"
        && !(builtins.elem name exclude)
        && (if includeDirs then isModuleDir name || isModuleFile name else isModuleFile name);
    in
    builtins.map (name: dir + "/${name}") (builtins.filter keep (builtins.attrNames entries));

  # fzf parses FZF_*_OPTS values as its own CLI options and treats a '#' at
  # the start of a token (after whitespace, outside quotes) as a comment that
  # silently drops the rest of the string — all colors/binds after it vanish
  # with no error. Guard so an inline '# ...' comment fails evaluation.
  # (Regression: commit 5cd4942a shipped such a comment inside FZF_DEFAULT_OPTS.)
  hasFzfHashComment =
    s:
    let
      # Drop single/double-quoted spans — fzf treats '#' inside quotes literally.
      stripQuoted =
        s':
        let
          len = builtins.stringLength s';
          go =
            i: inQ: acc:
            if i >= len then
              acc
            else
              let
                c = builtins.substring i 1 s';
              in
              if inQ != null then
                if c == inQ then go (i + 1) null acc else go (i + 1) inQ acc
              else if c == "'" || c == "\"" then
                go (i + 1) c acc
              else
                go (i + 1) null (acc ++ [ c ]);
        in
        builtins.concatStringsSep "" (go 0 null [ ]);
    in
    builtins.match "#.*" s != null || builtins.match ".*[[:space:]]#.*" (stripQuoted s) != null;

  guardFzfOpts =
    name: value:
    if hasFzfHashComment value then
      throw "environment.variables.${name}: contains a standalone '#' token — fzf treats it as a comment and silently drops everything after it (colors, binds). Remove the inline comment."
    else
      value;

  # ЙЦУКЕН hotkey table + generators — single source of truth for Russian-layout
  # duplicate binds (see lib/ru-keys.nix and docs/howto/hotkeys-ru-layout.md).
  ruKeys = import ./ru-keys.nix;
}
