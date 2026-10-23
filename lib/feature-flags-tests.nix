# Pure assertions over the `lib.neg.enabled "<path>"` call sites — eval-only,
# wired into flake/checks.nix as the "feature-flags" check.
#
# `enabled` resolves `features.<path>.enable`; a path that no module declares
# (a typo, or an option declared without the `.enable` suffix) silently reads
# false, so the gate dies quietly instead of failing. That is how
# `lib.neg.enabled "security.lockKernelModules"` kept nixpkgs'
# security.lockKernelModules disabled no matter what the feature flag said
# (modules/features/security.nix declared it without `.enable`).
#
# Source discovery is a plain text scan of the .nix files under modules/ and
# hosts/: comment lines are skipped, and only single-line double-quoted calls
# are seen (a path built by interpolation is not checked — keep flags literal).
#
# modules/core/neg.nix is scanned separately for the unqualified form
# (`enabled "gui.qt"`): that is where the predicate is defined and called, and a
# flat `mkBool` flag there has no `.enable` for it to read — `x.enable or false`
# swallows the type error into false, which is how features.gui.wallpaperVideo
# stayed impossible to enable while every call site looked correct.
{
  lib,
  featuresOptions,
}:
let
  sources =
    lib.filesystem.listFilesRecursive ../modules ++ lib.filesystem.listFilesRecursive ../hosts;

  nixSources = builtins.filter (f: lib.hasSuffix ".nix" (toString f)) sources;

  # `lib.neg.enabled "gui.qt"` → "gui.qt"; null for every other line.
  flagOf =
    line:
    let
      stripped = lib.trim line;
      # builtins.match returns the capture list, so take its head (null-guarded).
      matched = builtins.match ".*lib\\.neg\\.enabled \"([^\"]+)\".*" line;
    in
    if lib.hasPrefix "#" stripped || matched == null then null else builtins.head matched;

  scannedFlags = lib.unique (
    lib.concatMap (
      f: lib.filter (p: p != null) (map flagOf (lib.splitString "\n" (builtins.readFile f)))
    ) nixSources
  );

  # Comments go first: this file's own header quotes `enabled "x"` in prose.
  negSource = ../modules/core/neg.nix;
  negCode = lib.concatMapStrings (line: "${builtins.head (lib.splitString "#" line)}\n") (
    lib.splitString "\n" (builtins.readFile negSource)
  );

  # Split on the call token rather than matching per line: the calls share lines
  # (`enabled "gui" && enabled "gui.qt" && …`) and a greedy builtins.match would
  # only ever see the last one.
  negFlags = lib.unique (
    lib.filter (p: p != null) (
      map (
        chunk:
        let
          matched = builtins.match "([^\"]+)\".*" chunk;
        in
        if matched == null then null else builtins.head matched
      ) (lib.drop 1 (lib.splitString "enabled \"" negCode))
    )
  );

  flags = lib.unique (scannedFlags ++ negFlags);

  # features.<path>.enable must exist as a declared option.
  resolves = p: lib.attrByPath (lib.splitString "." p ++ [ "enable" ]) null featuresOptions != null;

  unresolved = builtins.filter (p: !resolves p) flags;

  check = cond: msg: {
    inherit msg;
    ok = cond;
  };

  checks = [
    (check (scannedFlags != [ ]) "flag scan found at least one lib.neg.enabled call")
    # Guards the guard: renaming the local predicate would silently empty the
    # modules/core/neg.nix half of the scan.
    (check (negFlags != [ ]) "modules/core/neg.nix still calls enabled \"<path>\"")
    (check (unresolved == [ ]) (
      "every lib.neg.enabled path resolves to features.<path>.enable; unresolved: "
      + lib.concatStringsSep ", " unresolved
    ))
  ];
in
{
  inherit checks;
  failures = builtins.filter (c: !c.ok) checks;
  report = lib.concatStringsSep "; " (map (f: f.msg) (builtins.filter (c: !c.ok) checks));
}
