# AUR-ported release binaries, wired through per-package derivations
# (packages/<name>/default.nix). All packages are x86_64-linux release
# binaries fetched from upstream GitHub releases.
final: _: {
  ghgrab = final.callPackage ../ghgrab { };
  lazytail = final.callPackage ../lazytail { };
  reddix = final.callPackage ../reddix { };
  repeater = final.callPackage ../repeater { };
  resterm = final.callPackage ../resterm { };
  simutil = final.callPackage ../simutil { };
  strace-tui = final.callPackage ../strace-tui { };
  v2raya = final.callPackage ../v2raya { };
  watchtower = final.callPackage ../watchtower { };
  witr = final.callPackage ../witr { };
  zapret2 = final.callPackage ../zapret2 { };
}
