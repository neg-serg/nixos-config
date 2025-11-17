# Third-Party Components

This repository vendors several upstream projects and scripts. Keep this manifest in sync whenever
sources are updated so licenses and provenance stay clear.

## Packaged applications

| Component | Source | Revision | License | Notes |
|-----------|--------|----------|---------|-------| | **awrit** |
[github.com/chase/awrit](https://github.com/chase/awrit) | tag `awrit-native-rs-2.0.3` |
BSD-3-Clause | Terminal Chromium renderer; packaged via `pkgs.neg.awrit`. | | **cantata** |
[github.com/nullobsi/cantata](https://github.com/nullobsi/cantata) | commit
`a19efdf9649c50320f8592f07d82734c352ace9c` | GPL-3.0-only | MPD Qt client with icon/perl fixes,
exposed as `pkgs.neg.cantata`. | | **nix-qml-support** |
[git.outfoxxed.me/outfoxxed/nix-qml-support](https://git.outfoxxed.me/outfoxxed/nix-qml-support) |
commit `8f897ffb4a1575252c536c63db8be72f22b6a494` | *No license declared upstream* | Provides QML
tree-sitter grammar + `qml-ts-mode` for the custom Emacs build. |

## Kitty kittens & scripts

| Component | Source | Revision | License | Notes |
|-----------|--------|----------|---------|-------| | **kitty-kitten-search** (`search.py`,
`scroll_mark.py`) |
[github.com/trygveaa/kitty-kitten-search](https://github.com/trygveaa/kitty-kitten-search) |
`992c1f3d220dc3e1ae18a24b15fcaf47f4e61ff8` | *No license declared upstream* | Live incremental
search kitten; update scripts when upstream changes and verify licensing. |

If a new component is added (or a commit changes), append a row or update the entry and ensure the
applicable LICENSE file ships alongside any vendored source when required by the upstream license.
