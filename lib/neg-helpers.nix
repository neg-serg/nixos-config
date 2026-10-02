# Structural home-file helpers — pure functions with no config dependency.
# Single source of truth: flake/nixos.nix (specialArgs.neg) and
# flake/checks.nix import this file instead of inlining or stubbing them.
rec {
  # Home files for the primary user, applied via nix-maid (users.users.neg.maid)

  # ── Live (writable, instantly-applied) sources ───────────────────────────
  # Absolute path of the working copy. Pointing a home-file `source` here
  # instead of at its /nix/store copy makes the deployed link writable AND
  # turns "edit the repo" into "deployed": the symlink already points at the
  # file you just edited, so no rebuild/switch is in the loop. Returned as a
  # *string* on purpose — strings carry no path context, so the file is not
  # copied into the store and stays editable.
  liveRoot = "/etc/nixos";
  live = p: "${liveRoot}/${p}";

  mkHomeFiles = files: {
    users.users.neg.maid.file.home = files;
  };

  # Map `names` to home-file entries named `<destDir>/<name>`; `mkValue name`
  # builds each entry's value. Single home for the
  # `builtins.listToAttrs (map (name: { name = …; value = …; }))` block that
  # several modules used to open-code.
  mkDirEntries =
    destDir: names: mkValue:
    builtins.listToAttrs (
      map (name: {
        name = "${destDir}/${name}";
        value = mkValue name;
      }) names
    );

  # Symlink variant: `<destDir>/<name>` → `<sourceDir>/<name>`.
  mkDirLinks =
    destDir: sourceDir: names:
    mkDirEntries destDir names (name: {
      source = "${sourceDir}/${name}";
    });

  # Suffix test — shared by importDir and tree (it used to live inside
  # importDir only).
  hasSuffix =
    suf: s:
    let
      sLen = builtins.stringLength s;
      sufLen = builtins.stringLength suf;
    in
    sLen >= sufLen && builtins.substring (sLen - sufLen) sufLen s == suf;

  # Import modules from a directory — single replacement for the
  # `builtins.readDir ./. |> attrNames |> filter |> map` pipeline copied into
  # every auto-importing default.nix.
  #
  #   importDir { dir = ./.; }                      # flat *.nix files
  #   importDir { dir = ./.; includeDirs = true; }  # + module subdirectories
  #   importDir { dir = ./.; exclude = [ "x.nix" ]; }
  #   importDir { dir = ./.; nameFilter = n: n != "games"; }  # drop by name
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
      # Entry name -> bool (directories by their plain name, files with the
      # extension). modules/default.nix passes domainFilter here, so a domain
      # is dropped by NAME and the caller holds no path list.
      nameFilter ? (_: true),
    }:
    let
      entries = builtins.readDir dir;
      isModuleDir =
        name: entries.${name} == "directory" && builtins.pathExists (dir + "/${name}/default.nix");
      isModuleFile = name: entries.${name} != "directory" && hasSuffix ".nix" name;
      keep =
        name:
        name != "default.nix"
        && !(builtins.elem name exclude)
        && nameFilter name
        && (if includeDirs then isModuleDir name || isModuleFile name else isModuleFile name);
    in
    builtins.map (name: dir + "/${name}") (builtins.filter keep (builtins.attrNames entries));

  # importDomain DIR — the body of a per-domain aggregator: import every
  # *.nix file and every module subdirectory of DIR.
  #   { neg, ... }: neg.importDomain ./.
  importDomain = dir: {
    imports = importDir {
      inherit dir;
      includeDirs = true;
    };
  };

  # tree { dir, extensions ? [ ".nix" ] } — the same directory as an attribute
  # set keyed by short names: the by-name half of the path story (importDir
  # above is the import-list half). Callers address a file by name instead of
  # counting `../..` segments:
  #
  #   (tree { dir = ./modules; }).core.default      → …/modules/core/default.nix
  #   (tree { dir = ./modules; }).core.neg          → …/modules/core/neg.nix
  #   (tree { dir = ./files; extensions = [ ".lua" ]; }).mpv."hdr-auto-switch"
  #
  # Conventions (import-tree/haumea rules, applied to every tree):
  #   - a directory recurses; its default.nix is exposed as that directory's
  #     `.default` (not as the whole value, so siblings stay reachable);
  #   - entries starting with "_" or "." are skipped (private data, hidden files);
  #   - the matching extension is stripped from the key, any other name is kept
  #     verbatim (so non-.nix data files stay addressable via `t."name.ext"`).
  tree =
    {
      dir,
      extensions ? [ ".nix" ],
    }:
    let
      entries = builtins.readDir dir;
      private = name: builtins.substring 0 1 name == "_" || builtins.substring 0 1 name == ".";
      # Longest matching extension wins, so [ ".nix" ".tar.gz" ] stays sane.
      stripExt =
        name:
        let
          hits = builtins.filter (ext: hasSuffix ext name) extensions;
        in
        if hits == [ ] then
          name
        else
          let
            ext = builtins.foldl' (
              a: b: if builtins.stringLength b > builtins.stringLength a then b else a
            ) (builtins.head hits) hits;
          in
          builtins.substring 0 (builtins.stringLength name - builtins.stringLength ext) name;
      node =
        name:
        let
          path = dir + "/${name}";
        in
        if entries.${name} != "directory" then
          path
        else
          let
            # A directory that carries default.nix keeps BOTH: the entry itself
            # (`.foo.default`) and its children (`.foo.bar`). Making the default
            # the whole value of `foo` would hide every sibling module behind it.
            hasDefault = builtins.pathExists (path + "/default.nix");
            sub = tree { dir = path; inherit extensions; };
          in
          if sub == { } && !hasDefault then
            null
          else
            (if hasDefault then { default = path + "/default.nix"; } else { }) // sub;
      keep =
        name:
        !(private name)
        && name != "default.nix"
        && (entries.${name} == "directory" || builtins.any (ext: hasSuffix ext name) extensions);
    in
    builtins.listToAttrs (
      builtins.filter (entry: entry.value != null) (
        builtins.map (name: {
          name = stripExt name;
          value = node name;
        }) (builtins.filter keep (builtins.attrNames entries))
      )
    );

  # systemdUser LIB — the per-user systemd unit helpers (lib/systemd-user.nix)
  # as a factory. Sibling file, resolved here so callers in a top-level `let`
  # can build it without a relative import and without touching `config`, which
  # does not exist yet while a module is being collected (using
  # config.lib.neg.systemdUser there is an infinite recursion).
  systemdUser = lib: import ./systemd-user.nix { inherit lib; };

  # leaves TREE — flatten it to [{ name = <last key>; path = [ <keys> … ]; value = <path>; }],
  # the index `find` searches. `name` is the final key segment, `path` the full
  # key chain, so an error message can say exactly where the match was.
  leaves =
    t:
    builtins.concatLists (
      builtins.map (
        name:
        let
          value = t.${name};
        in
        if builtins.isAttrs value then
          builtins.map (leaf: leaf // { path = [ name ] ++ leaf.path; }) (leaves value)
        else
          [
            {
              inherit name value;
              path = [ name ];
            }
          ]
      ) (builtins.attrNames t)
    );

  # find TREE "name" — resolve a short name (last key segment, with or without
  # the ".nix" suffix) to its path. A miss and an ambiguity are both eval errors
  # that print the candidates, so the fix is a one-line edit:
  #
  #   import (find libTree "systemd-user") { inherit lib; }
  find =
    t: name:
    let
      # "systemd-user", "systemd-user.nix" and "caches.nix" all resolve: the
      # key drops ".nix", the caller usually types the file name.
      hits = builtins.filter (
        leaf: leaf.name == name || leaf.name == "${name}.nix" || "${leaf.name}.nix" == name
      ) (leaves t);
      at =
        leaf:
        "${builtins.concatStringsSep "." leaf.path} → ${toString leaf.value}";
    in
    if builtins.length hits == 1 then
      (builtins.head hits).value
    else if hits == [ ] then
      throw "neg.find: nothing named '${name}' here (top level: ${builtins.concatStringsSep ", " (builtins.attrNames t)})"
    else
      throw "neg.find: '${name}' matches ${toString (builtins.length hits)} entries — ${builtins.concatStringsSep ", " (map at hits)}";

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
