# Dev Module

Development tools, languages, and security research utilities.

## Structure

| Directory | Purpose |
|-----------|---------|
| `android/` | Android SDK and tools |
| `benchmarks/` | System benchmarking |
| `editor/` | Code editors |
| `elf/` | ELF binary analysis |
| `gcc/` | GCC toolchain |
| `gdb/` | GDB debugger |
| `git/` | Git configuration |
| `hack/` | Security research (19 modules) |
| `openxr/` | OpenXR development |
| `pkgs/` | Development packages |
| `python/` | Python ecosystem |
| `unreal/` | Unreal Engine |

## Key Submodules

### hack/

Security research toolkit:

- **Forensics** — disk/memory analysis
- **Pentest** — recon, fuzzing, passwords, web, wireless
- **Reverse engineering** — disassemblers, debuggers

### python/

Python development:

- Linters (ruff, pyright)
- Formatters (black, isort)
- Virtual environment tools

## Feature Toggle

```nix
features.dev.enable = true;  # Enable dev tools
```
