# Lib

Custom Nix library functions.

## Provides

Core helpers used across the configuration:

| Function | Purpose | |----------|---------| | `mkWhen` | Conditional merging | | `mkUnless` |
Inverse conditional | | `mkXdgText` | XDG file creation | | `mkLocalBin` | Script installation | |
`mkHomeFiles` | Home directory files | | `mkEnsureRealDir` | Directory creation |

## Files

- `neg.nix` — Main helper library
- `xdg-helpers.nix` — XDG-related functions
- `opts.nix` — Option helpers

## Usage

```nix
config.lib.neg.mkWhen condition { ... }
config.lib.neg.mkLocalBin "script-name" "script content"
```
