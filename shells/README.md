# Dev Shells

Nix development shells for various projects.

## Available Shells

| Shell | Purpose | |-------------|----------------------| | `comfy` | ComfyUI development | |
`python` | Python development | | `tarantool` | Tarantool database |

## Usage

```bash
# Enter a shell
nix develop .#comfy
nix develop .#python

# Or from the shells directory
cd shells/python && nix develop
```
