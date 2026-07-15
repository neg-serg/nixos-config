# Slimmed nixpkgs Fork — Eval Time Reduction Plan

## TL;DR

Создать форк nixpkgs, из которого выброшены ВСЕ модули и пакеты, не используемые конфигурацией odin. Сейчас nixpkgs загружает 2047 модулей, из которых реально нужны ~100-150. Удаление 90%+ модулей напрямую сократит `applyModuleArgs`, `binaryMerge`, и другие eval-hotspots которые по flamegraph-у занимают ~30% времени.

**Ожидаемый эффект**: 4.3s → 2.0-2.5s (экономия ~2s на инфраструктуре модулей nixpkgs)

**Риск**: ошибки «missing option» при удалении модуля, который транзитивно нужен

## Подход

### Шаг 1: Создать форк nixpkgs
- Взять тот же коммит, что в `flake.lock` 
- Создать репозиторий `github:neg-serg/nixpkgs-slim`
- Настроить CI для автообновления (pull upstream, re-apply stripping)

### Шаг 2: Категоризировать нужные модули

Из 2047 модулей в module-list.nix определить какие нужны:

| Категория | Файлов | Нужно? | Пример |
|-----------|--------|--------|--------|
| config/* | ~50 | ВСЕ | system-path.nix, users-groups.nix, ...
| hardware/* | ~80 | ~30 | cpu/amd.nix ✅, printer/cupsd.nix ❌ |
| services/* | ~1477 | ~40 | openssh ✅, postgresql ❌ |
| system/boot/* | ~100 | ~50 | loader/systemd-boot ✅ |
| system/etc/* | ~6 | ВСЕ | etc.nix, nix.nix |
| virtualisation/* | ~40 | ~5 | none for odin except LXC |
| programs/* | ~60 | ~15 | zsh ✅, ssh ✅, kdeconnect ✅ |
| security/* | ~30 | ~10 | polkit ✅, sudo ✅ |
| tasks/* | ~15 | ~8 | filesystems ✅, swap ✅ |
| misc/* | ~15 | ~5 | nixpkgs.nix, version.nix |
| testing/* | ~10 | 0 | только для CI |
| profiles/* | ~10 | ~3 | qemu-guest ❌ (мы не VM) |
| installer/* | ~15 | 0 | не нужны |

**Итого нужно**: ~100-150 модулей из 2047 (~5-7%)

### Шаг 3: Методология проверки

Итеративный процесс:
1. Начинаем с ПОЛНОГО module-list.nix
2. Комментируем один файл
3. `nix eval --refresh --offline` — проверяем что eval работает
4. Если ошибка «attribute X missing» или «option not found» — раскомментируем
5. Повторяем для каждого файла

Автоматизация через скрипт:
```bash
for module in $(find nixos/modules -name "*.nix" -path "*/services/*"); do
  # temporary remove, test, restore if fails
done
```

### Шаг 4: Замена в flake.nix

```nix
nixpkgs.url = "github:neg-serg/nixpkgs-slim/main";
# Вместо: nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
```

### Шаг 5: Автообновление

CI pipeline:
- Каждую неделю pull из upstream nixpkgs
- Re-apply stripping скрипт
- Проверить что `nh os switch --dry` проходит
- Автоматический PR в nixpkgs-slim

## Todos

### 1. Создать репозиторий nixpkgs-slim и клонировать текущий nixpkgs

- Взять коммит из flake.lock
- Создать `github.com/neg-serg/nixpkgs-slim`
- Скопировать ВСЕ файлы (полный форк)

### 2. Собрать полный список нужных модулей

- Пройти по ВСЕМ категориям module-list.nix
- Для каждой категории определить какие модули оставить
- Использовать:
  - Список включённых сервисов (~36)
  - `grep -r "config\." modules/ hosts/ --include='*.nix' -o | sort -u` для всех используемых опций
  - Здравый смысл (очевидно ненужное: CI, installer, тестирование)
- Получить список ~100-150 модулей

### 3. Создать скрипт для автоматического определения зависимостей

- Скрипт который: комментирует модули по одному → проверяет eval → логирует
- Отчёт какие модули безопасно удалить, какие нет
- Остановиться когда все модули проверены

### 4. Обновить flake.nix — указать на slim nixpkgs

- `nixpkgs.url = "github:neg-serg/nixpkgs-slim/main"`
- `nix flake lock --update-input nixpkgs`
- Проверить что `nh os switch --dry` проходит

### 5. Замерить eval время

- До и после
- Ожидание: 4.3s → 2.0-2.5s

### F1. Regression: полный цикл

- `nh os switch --dry`
- `nix flake check`
- `nix build .#nixosConfigurations.odin.config.system.build.toplevel`

## Must-NOT-Have
- Не удалять модули от которых зависит systemd target default
- Не удалять модули от которых зависит stage-1/initrd
- Не пропускать модули которые нужны транзитивно (e.g. networking.firewall нужен даже если явно не referenced)
- Не коммитить в nixpkgs-slim без проверки
