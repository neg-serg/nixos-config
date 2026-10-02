# Packages

Custom packages and overlays for the configuration.

## Structure

| Directory | Purpose | |-----------|---------| | `overlay.nix` | Main overlay entry | | `overlays/`
| Overlay helpers (functions, tools, media, gui, aur-ported) | | `local-bin/` | User scripts for
`~/.local/bin` | | `game/` | Rust gaming launcher (CPU pinning, gamescope presets) |

## Usage

Packages are available via `pkgs.<name>` or `pkgs.neg.<name>`:

```nix
environment.systemPackages = [ pkgs.flight-gtk-theme ];
```

## Adding Packages

1. Create `packages/my-package/default.nix`
1. Add to `packages/overlay.nix`
1. Reference via `pkgs.my-package`

## Referencing repo files

A package never counts `../..` levels: declare `paths` as a formal and the shared
`neg.functions.callPkg` fills it in (same sniffing as `inputs`) — or pass it explicitly
(`prev.callPackage ../vstplugin { inherit paths; }`). The value is the repo-root resolver from
`lib/neg-helpers.nix`, built once in `overlay.nix`.

```nix
{
  stdenv,
  paths,
}:
stdenv.mkDerivation {
  src = paths.path "files/sources/foo-1.0.tar.gz";
}
```

`paths` also answers by name — `paths.tree { dir = "files"; extensions = "any"; }` — and
`paths.find "files" "foo-1.0"` resolves a short name. A sibling package stays
`callPackage ../sibling { }`: one level up inside this tree cannot drift out of it.
