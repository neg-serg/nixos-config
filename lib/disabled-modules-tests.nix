# Eval-only guard over modules/system/disabled-modules.nix.
#
# NixOS matches a `disabledModules` entry against module keys and silently
# ignores one that matches nothing (`isDisabledModule = elem key disabledKeys`
# in lib/modules.nix). A module that moved or disappeared upstream therefore
# stops being disabled without any warning: the list keeps looking deliberate
# while the module is imported again. This suite resolves every active entry
# against the pinned nixpkgs and rejects duplicates, so a nixpkgs bump that
# moves a module fails `just check` instead of quietly widening the eval tree.
{ nixpkgs }:
let
  t = import ./test-suite.nix;
  inherit (t) check;
  entries = (import ../modules/system/disabled-modules.nix) { };
  modulesDir = nixpkgs + "/nixos/modules";
  missing = builtins.filter (
    m: !(builtins.pathExists (modulesDir + "/${m}"))
  ) entries.disabledModules;
  duplicated = builtins.filter (
    m: builtins.length (builtins.filter (x: x == m) entries.disabledModules) > 1
  ) entries.disabledModules;
in
t.suite [
  (check (missing == [ ])
    "every disabledModules entry resolves under nixos/modules: ${builtins.concatStringsSep ", " missing}"
  )
  (check (
    duplicated == [ ]
  ) "no duplicate disabledModules entries: ${builtins.concatStringsSep ", " duplicated}")
]
