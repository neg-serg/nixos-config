# Core Module / Основной модуль

## EN

This module provides core configuration options and library functions for the entire NixOS configuration.

### Contents

- `neg.nix` — Defines global options under `neg.*` namespace and exposes helper functions via `lib.neg`

### Options

| Option | Type | Description |
|--------|------|-------------|
| `neg.repoRoot` | string | Path to the configuration repository root (default: `/etc/nixos`) |
| `neg.rofi.package` | package | The rofi package to use system-wide |

---

## RU

Модуль предоставляет основные параметры конфигурации и библиотечные функции для всей конфигурации NixOS.

### Содержимое

- `neg.nix` — Определяет глобальные опции в пространстве имён `neg.*` и предоставляет вспомогательные функции через `lib.neg`

### Опции

| Опция | Тип | Описание |
|-------|-----|----------|
| `neg.repoRoot` | строка | Путь к корню репозитория конфигурации (по умолчанию: `/etc/nixos`) |
| `neg.rofi.package` | пакет | Пакет rofi для использования в системе |
