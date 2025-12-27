# Dev Module / Модуль разработки

Development tools, languages, and security research utilities.

Инструменты разработки, языки и утилиты для исследования безопасности.

## Structure / Структура

| Directory | Purpose / Назначение | |-----------|---------| | `android/` | Android SDK and tools |
| `benchmarks/` | System benchmarking / Бенчмарки | | `editor/` | Code editors / Редакторы кода | |
`elf/` | ELF binary analysis / Анализ ELF | | `gcc/` | GCC toolchain | | `gdb/` | GDB debugger /
Отладчик | | `git/` | Git configuration / Конфигурация Git | | `hack/` | Security research (19
modules) / Безопасность | | `openxr/` | OpenXR development | | `pkgs/` | Development packages /
Пакеты | | `python/` | Python ecosystem | | `unreal/` | Unreal Engine |

## Key Submodules / Ключевые подмодули

### hack/

Security research toolkit / Инструменты безопасности:

- **Forensics** — disk/memory analysis / Анализ дисков/памяти
- **Pentest** — recon, fuzzing, passwords, web, wireless
- **Reverse engineering** — disassemblers, debuggers

### python/

Python development:

- Linters (ruff, pyright)
- Formatters (black, isort)
- Virtual environment tools

## Feature Toggle / Переключатель

```nix
features.dev.enable = true;  # Enable dev tools / Включить
```
