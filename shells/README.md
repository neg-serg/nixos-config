# Dev Shells / Среды разработки

Nix development shells for various projects.

Nix-среды разработки для различных проектов.

## Available Shells / Доступные среды

| Shell | Purpose / Назначение |
|-------|---------------------|
| `comfy` | ComfyUI development |
| `python` | Python development |
| `tarantool` | Tarantool database |

## Usage / Использование

```bash
# Enter a shell / Войти в среду
nix develop .#comfy
nix develop .#python

# Or from the shells directory / Или из директории shells
cd shells/python && nix develop
```
