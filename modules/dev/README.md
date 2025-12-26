# Dev Module

Development tools, languages, and security research utilities.

## Structure

| Directory | Purpose |
|-----------|---------|
| `android/` | Android SDK and tools |
| `benchmarks/` | System benchmarking tools |
| `editor/` | Code editors configuration |
| `elf/` | ELF binary analysis tools |
| `gcc/` | GCC toolchain |
| `gdb/` | GDB debugger config |
| `git/` | Git configuration and tools |
| `hack/` | Security research and pentesting (19 modules) |
| `openxr/` | OpenXR development |
| `pkgs/` | Development packages |
| `python/` | Python ecosystem |
| `unreal/` | Unreal Engine development |

## Key Submodules

### hack/

Security research toolkit with:
- **Forensics** — disk/memory analysis
- **Pentest** — recon, fuzzing, passwords, web, wireless
- **Reverse engineering** — disassemblers, debuggers

### git/

Git configuration with delta diff viewer and custom aliases.

### python/

Python development with:
- Linters (ruff, pyright)
- Formatters (black, isort)
- Virtual environment tools

## Feature Toggle

```nix
features.dev.enable = true;  # Enable dev tools
```
