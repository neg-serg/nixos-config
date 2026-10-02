# Pure assertions over lib/neg-helpers.nix — eval-only, no filesystem writes.
# Wired into flake/checks.nix as the "neg-tree-guard" check.
#
# The guard pins the by-name resolver (tree / leaves / find) and importDir's
# nameFilter, i.e. the machinery that lets call sites say `neg.find t "x"`
# instead of counting `../..` segments. Paths here are relative to this file
# (lib/) on purpose: a test is allowed to know where it sits.
let
  neg = import ./neg-helpers.nix;

  libTree = neg.tree { dir = ./.; };
  modules = neg.tree { dir = ../modules; };
  luaTree = neg.tree {
    dir = ../files/mpv;
    extensions = [ ".lua" ];
  };
  binTree = neg.tree {
    dir = ../packages/local-bin/bin;
    extensions = [ ".sh" ];
  };
  anyTree = neg.tree {
    dir = ../files/mpv;
    extensions = "any";
  };
  artTree = neg.tree {
    dir = ../files/art/fun-art;
    extensions = "any";
  };
  rooted = neg.rooted ../.;

  missing = builtins.tryEval (neg.find libTree "definitely-not-a-file");
  leaf = name: t: builtins.head (builtins.filter (l: l.name == name) (neg.leaves t));

  check = cond: msg: {
    inherit msg;
    ok = cond;
  };

  checks = [
    # tree: names instead of paths; default.nix addresses its own directory
    (check (modules ? core) "a directory becomes a key")
    (check (
      modules.core.default == ../modules/core/default.nix
    ) "default.nix is exposed as <dir>.default")
    (check (modules.core.neg == ../modules/core/neg.nix) "siblings stay addressable next to it")
    (check (
      neg.tree { dir = ../packages/local-bin/bin; } == { }
    ) "a directory with nothing addressable disappears")
    (check (libTree ? systemd-user) "the .nix extension is stripped from the key")

    # extensions: non-.nix data files are addressable too, without camel-casing
    (check (luaTree ? "hdr-auto-switch") "extensions selects a second addressable file kind")
    (check (
      luaTree."hdr-auto-switch" == ../files/mpv/hdr-auto-switch.lua
    ) "a non-.nix key keeps its dashes and resolves to the file")

    # extensions = "any": every regular file, last extension stripped
    (check (anyTree ? mpv) "extensions = \"any\" takes files of every kind (mpv.conf → mpv)")
    (check (anyTree ? input) "…and strips the last extension (input.conf → input)")

    # two entries wanting one key → both keep their full names (nothing shadowed)
    (check (artTree ? "skull.sh" && artTree ? "skull.txt") "colliding keys keep their full names")
    (check (!(artTree ? skull)) "the colliding short key is not invented")

    # rooted: the same vocabulary for call sites without `config`
    (check (rooted.path "lib/opts.nix" == ./opts.nix) "rooted resolves against its root")
    (check (
      builtins.head (builtins.split "\n" (rooted.readFile "lib/opts.nix")) == "{ lib }:"
    ) "rooted reads a repo file")
    (check (rooted.pathExists "lib/opts.nix") "rooted.pathExists finds a present file")
    (check (!rooted.pathExists "lib/not-here.nix") "rooted.pathExists reports a missing one")
    (check ((rooted.find "lib" "opts") == ./opts.nix) "rooted.find takes a repo-relative dir")
    (check ((rooted.tree { dir = "lib"; }).opts == ./opts.nix) "rooted.tree takes a repo-relative dir")

    # "_"-prefix is the private/hidden convention (same as import-tree/haumea)
    (check (!(binTree ? _localbin)) "underscore-prefixed entries are skipped")
    (check (binTree ? swayimg-actions) "the sibling .sh file is still addressable")

    # find: bare name or file name, and a miss is an error, not a null
    (check (neg.find libTree "systemd-user" == ./systemd-user.nix) "find resolves a bare name")
    (check (neg.find libTree "systemd-user.nix" == ./systemd-user.nix) "find accepts the file name")
    (check (!missing.success) "a miss aborts evaluation")

    # leaves: the flat index find searches (name + full key path)
    (check ((leaf "systemd-user" libTree).path == [ "systemd-user" ]) "leaves carry the key path")
    (check (
      (leaf "neg" modules).path == [
        "core"
        "neg"
      ]
    ) "leaves carry the nested key path")

    # importDir nameFilter: the hook modules/default.nix uses for domainFilter
    (check (
      neg.importDir {
        dir = ./.;
        nameFilter = n: n == "opts.nix";
      } == [ ./opts.nix ]
    ) "nameFilter keeps only the named entry")
    (check (
      neg.importDir {
        dir = ./.;
        nameFilter = _: false;
      } == [ ]
    ) "nameFilter can drop every entry")
  ];
in
{
  inherit checks;
  failures = builtins.filter (c: !c.ok) checks;
  report = builtins.concatStringsSep "; " (map (f: f.msg) (builtins.filter (c: !c.ok) checks));
}
