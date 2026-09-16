# AUR-ported release binaries, wired through per-package derivations
# (packages/<name>/default.nix). All packages are x86_64-linux release
# binaries fetched from upstream GitHub releases.
final: _: {
  zapret2 = final.callPackage ../zapret2 { };
}
