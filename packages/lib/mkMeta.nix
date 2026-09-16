# Shared `meta` builder for the local packages in packages/*/default.nix.
#
# Reachable as `lib.mkMeta` (overlays/functions.nix extends pkgs.lib) and under
# pkgs.neg.functions.mkMeta. It defaults the two fields that are identical for
# almost every package in this tree — `platforms` to Linux-only and
# `maintainers` to the empty list (nothing here is upstream, see
# packages/AGENTS.md) — so a package file lists only the fields that differ:
#
#   meta = lib.mkMeta {
#     description = "...";
#     homepage = "...";      # optional
#     license = lib.licenses.mit;
#     mainProgram = "flow";  # optional, like any other meta attribute
#   };
#
# Pass `platforms`/`maintainers` explicitly whenever they differ from the
# defaults (lib.platforms.all, lib.platforms.unix, a system list, real
# maintainers); any other attribute (longDescription, ...) passes through
# unchanged, and an omitted `homepage` leaves the attribute out entirely.
{
  lib,
}:
{
  description,
  homepage ? null,
  license,
  platforms ? lib.platforms.linux,
  maintainers ? [ ],
  ...
}@args:
{
  inherit
    description
    license
    platforms
    maintainers
    ;
}
// lib.optionalAttrs (homepage != null) { inherit homepage; }
// builtins.removeAttrs args [
  "description"
  "homepage"
  "license"
  "platforms"
  "maintainers"
]
