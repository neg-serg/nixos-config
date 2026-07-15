# Eval Speedup Plan v2 — 4.3s → ~2.5s

## TL;DR (For humans)

Цель: ускорить `nix eval --refresh --offline '.#nixosConfigurations.odin.config.system.build.toplevel.name'` с 4.3s до ~2.5s.

**Что реально замедляет eval (по итогам профилирования и ревью):**

| Драйвер | Вклад | Что делаем |
|---------|-------|-----------|
| `builtins.pathExists` (~15 вызовов ФС на каждом eval) | ~0.6s | Оборачиваем в ленивый `mkIf` — не форсим IO при импорте |
| 5 тестовых `nixosSystem` в `nixosConfigurations` | ~0.3s | Переносим в `checks` — не форсятся при обычном eval |
| `per-system.nix` (654 строки, 50+ devShells) | ~0.3s | Разделяем на отдельные файлы, лёгкий `perSystem` |
| 10 re-export wrapper-ов + пустые домены | ~0.2s | Сливаем/удаляем — меньше файлов, меньше import() |
| 14 `assertParent` + мёртвая `mkIf(!hack)` | ~0.1s | Чистим мёртвый код, assertions не трогаем (уже скипаются) |

**Итого: ~1.5s экономии → цель ~2.8s (±0.3s).**

**Что НЕ вошло (после ревью):**
- ❌ `builtins.seq` ленивость — не работает в flake-ах (Nix форсит все outputs)
- ❌ Перенос assertions в отдельный файл — нулевой выигрыш (`_module.check` и так false)
- ❌ Слияние `hardware/qmk/default.nix` и `hardware/video/pkgs/default.nix` — это НЕ wrapper-ы
- ❌ Переименование feature-опций — слишком большой blast radius (~170 референсов), выигрыш мизерный

## Todos

### Wave 1 — IO + структурные (~1.2s)

### 1. Ленивые `builtins.pathExists` — крупнейший источник тормозов
- **Файлы**: `modules/user/nix-maid/sys/secrets.nix`, `hosts/odin/services.nix`, `modules/user/nix-maid/apps/opencode.nix`, `modules/user/nix-maid/cli/local-bin.nix`
- **Проблема**: `builtins.pathExists` вызывается на верхнем уровне модуля (~15 вызовов), форсит IO при каждом eval, бьёт eval-кэш
- **Фикс**: обернуть каждый `pathExists` в `let`-биндинг внутри `config` блока, чтобы проверка происходила только когда опция реально читается:
  ```nix
  # Было (на верхнем уровне):
  hasGithubToken = builtins.pathExists "${secretsDir}/github-token.sops.yaml";
  
  # Стало (внутри config.mkIf):
  config = lib.mkIf (builtins.pathExists "${secretsDir}/github-token.sops.yaml") {
    ...
  };
  ```
- **Конкретно**:
  - `secrets.nix`: 6 pathExists → внутрь соответствующих `mkIf` блоков
  - `services.nix`: 5 pathExists → внутрь `mkIf`
  - `opencode.nix`: 1 pathExists → внутрь `mkIf`
  - `local-bin.nix`: 3 pathExists → внутрь `mkIf`
- **Acceptance**: время eval падает на ≥0.4s
- **QA**: `nix eval --refresh --offline '.#nixosConfigurations.odin.config.system.build.toplevel.name'` до/после, сравнить

### 2. Перенести тестовые nixosConfigurations в checks
- **Файлы**: `flake/nixos.nix` (lines 183–226), `flake/checks.nix`
- **Проблема**: 5 тестовых конфигов (`odin-lite`, `odin-server`, `odin-gaming`, `odin-audio-pro`, `odin-server`-дубликат) форсят attrset-конструкцию при каждом eval
- **Фикс**:
  1. Удалить `prefixedTestConfigs` и генерацию тестовых конфигов из `flake/nixos.nix`
  2. `lib.genAttrs hostNamesEnabled mkHost` → `{ odin = mkHost "odin"; }`
  3. Экспортировать `mkTestHost` из `flake/nixos.nix`
  4. В `checks.nix` добавить проверки: `check-odin-lite`, `check-odin-gaming`, `check-odin-audio-pro` — каждый вызывает `mkTestHost` с domain filter
- **Acceptance**: `nix eval --json '.#nixosConfigurations' | jq 'keys'` → только `["odin"]`
- **QA**: 
  - `nix eval --json '.#checks.x86_64-linux' | jq 'keys'` — проверить что тестовые конфиги в checks
  - `nix flake check` — все проверки проходят (dry eval)

### 3. Разделить `per-system.nix` на лёгкие файлы
- **Файлы**: `flake/per-system.nix` (654 строки), новые `flake/dev-shells.nix`, `flake/packages.nix`
- **Проблема**: 654-строчный `per-system.nix` — каждый вызов форсит парсинг ВСЕХ devShells даже когда нужен только `packages` или `formatter`
- **Фикс**:
  1. Вынести devShells в `flake/dev-shells.nix` (функция: `{ self, inputs, nixpkgs, flakeLib, pkgs }: system: { ... 50+ devShells ... }`)
  2. Вынести packages в `flake/packages.nix` (функция: `{ self, inputs, ... }: system: { ... }`)
  3. `per-system.nix` оставляет только: `formatter`, `apps`, `checks` + импортирует `dev-shells.nix` и `packages.nix`
  4. `flake.nix` обновить: `devShells = lib.genAttrs supportedSystems (s: (import ./flake/dev-shells.nix { ... } s));`
- **Acceptance**: `nix flake show` показывает все devShells, `nix develop .#python` работает
- **QA**: `nix develop .#default`, `nix develop .#python`, `nix develop .#rust`, `nix develop .#haskell`, `nix develop .#node` — все возвращают exit 0

### 4. Убрать мёртвую ветку `mkIf(!hack.enable)` и backward compat
- **Файл**: `modules/features/default.nix`
- **Проблема**: 
  - Строки 128-130: `mkIf (!config.features.hack.enable) { features.hack = { }; }` — пустой attrset, ничего не делает
  - Строки 36-46: backward compat `profile → profiles` — уже не нужен (все хосты используют `profiles`)
- **Фикс**: удалить обе ветки
- **Acceptance**: `nix eval ...` без ошибок
- **QA**: `nh os switch --dry-run` проходит

### Wave 2 — Консолидация модулей (~0.3s)

### 5. Слить 6 подтверждённых re-export wrapper-ов
- **Проблема**: 6 файлов — это 4-строчные `{ imports = [ ./pkgs.nix ]; }` без логики. Лишние `import()` на eval.
- **Файлы и фикс** (переименовать `pkgs.nix` → `default.nix`, удалить старый `default.nix`):
  - `hardware/cpu/default.nix` (4 строки) → `hardware/cpu/default.nix` = старый `pkgs.nix`
  - `hardware/io/default.nix` (4 строки) → аналогично
  - `hardware/webcam/default.nix` (4 строки) → аналогично
  - `hardware/audio/dsp/default.nix` (4 строки) → аналогично
  - `dev/gcc/default.nix` (4 строки) → `dev/gcc/default.nix` = старый `autofdo.nix`
  - `dev/git/default.nix` (4 строки) → `dev/git/default.nix` = старый `pkgs.nix`
- **НЕ трогаем** (по результатам ревью):
  - `hardware/qmk/default.nix` — 105 строк, реальная логика
  - `hardware/video/pkgs/default.nix` — реальный модуль с `environment.systemPackages`
  - `hardware/audio/default.nix` — multi-import aggregator
  - `flatpak/default.nix` — 29 строк, не чистый wrapper
- **Acceptance**: 6 файлов удалено. `nix eval ...` без ошибок.
- **QA**: `nh os switch --dry-run`

### 6. Слить features-data unfree категории + документацию
- **Файлы**: `modules/features-data/unfree/categories/*.nix` (8 файлов), `modules/documentation/default.nix` (4 строки)
- **Проблема**: 8 одно-строчных файлов + 1 re-export wrapper
- **Фикс**:
  1. Объединить 8 категорий в `modules/features-data/unfree/categories.nix`:
     ```nix
     {
       ai-tools = [ ... ];
       audio = [ ... ];
       browsers = [ ... ];
       forensics = [ ... ];
       forensics-analysis = [ "volatility3" ];
       forensics-stego = [ "stegsolve" ];
       iac = [ "terraform" ];
       misc = [ "abuse" ];
     }
     ```
  2. Обновить `unfree-presets.nix` — импортировать один файл вместо 8
  3. `documentation/default.nix` (4 строки) → переименовать `settings.nix` в `default.nix`
  4. Удалить все исходные файлы + старый `documentation/default.nix`
- **Acceptance**: 9 файлов удалено (8 категорий + 1 wrapper)
- **QA**: `nix eval '.#packages.x86_64-linux.docs-modules'` — генерация OPTIONS.md всё ещё работает

### 7. Удалить пустые домены
- **Файлы**: `modules/finance/` (директория), `modules/db/` (директория), `modules/features/services.nix`
- **Проблема**: 
  - `finance/default.nix` — 4 строки, `imports = [];` — ничего не делает
  - `db/` — директория без `.nix` файлов
  - `services.nix` строка ~16: `features.finance = { };` — пустая опция
- **Фикс**:
  1. Удалить `modules/finance/` и `modules/db/`
  2. Удалить `features.finance = { };` из `modules/features/services.nix`
  3. Проверить: ни `modules/default.nix`, ни `flake/nixos.nix` НЕ содержат ссылок на finance/db (уже проверено — не содержат)
- **Acceptance**: сборка без ошибок, `grep -r "finance\|modules/db" modules/ flake/ hosts/` → только безвредные упоминания (комментарии/README)
- **QA**: `nh os switch --dry-run`

### Wave 3 — Прочее (~0.1s)

### 8. Убрать лишние mkIf-слияния в фичах
- **Файл**: `modules/features/default.nix`
- **Проблема**: 3 отдельных `mkIf` для `excludePkgs` (Haskell, Rust, C++) — можно слить в один
- **Фикс**: объединить в одну ветку:
  ```nix
  (mkIf (!devHaskell || !devRust || !devCpp) {
    features.excludePkgs = mkAfter (
      lib.optionals (!devHaskell) [ "ghc" "cabal-install" ... ]
      ++ lib.optionals (!devRust) [ "rustup" "rust-analyzer" ... ]
      ++ lib.optionals (!devCpp) [ "gcc" "cmake" ... ]
    );
  })
  ```
- **Acceptance**: 3 mkIf → 1 mkIf. Поведение идентично.
- **QA**: `diff <(nix eval .#nixosConfigurations.odin.config.features.excludePkgs --raw) <(git stash; nix eval ...)`

### 9. Собрать разбросанные feature-опции в `modules/features/`
- **Файлы для перемещения опций**: `modules/system/virt.nix`, `modules/flatpak/pkgs.nix`, `modules/hardware/liquidctl.nix`, `modules/hardware/usb-automount.nix`
- **Проблема**: 7 опций объявлены вне `modules/features/`, что заставляет модульную систему грузить эти файлы даже когда их домен не активен
- **Фикс**: перенести ТОЛЬКО `options.features.*` блоки в соответствующие файлы `modules/features/`:
  - `features.virt.*` → `modules/features/system.nix`
  - `features.flatpak.builder.enable` → `modules/features/misc.nix`
  - `features.hardware.liquidctl.*` → `modules/features/hardware.nix`
  - `features.hardware.usbAutomount.enable` → `modules/features/hardware.nix`
- **Acceptance**: все опции доступны по старым путям, `grep -r "options.features" modules/ --include='*.nix' | grep -v modules/features/` → пусто
- **QA**: `nh os switch --dry-run`

### Verification

### F1. Замеры времени на каждом шаге
- **Методология**:
  ```bash
  # Для каждого wave (после коммита изменений волны):
  hyperfine --warmup 3 --min-runs 10 \
    "nix eval --refresh --offline '.#nixosConfigurations.odin.config.system.build.toplevel.name'"
  ```
- **Target**: Wave 1 → ≤3.5s, Wave 2 → ≤3.0s, Wave 3 → ≤2.8s
- **QA**: Записать медиану и stddev для каждого wave в `.omo/drafts/eval-speedup.md`

### F2. Regression — полный цикл
- **Что**: `nh os switch --dry-run` + `nix flake check`
- **QA**: Обе команды успешны после каждого wave

### F3. Regression — devShells
- **Что**: `nix develop .#default`, `.#python`, `.#rust`, `.#haskell`, `.#node` — каждый с `--command true`
- **QA**: Все exit 0

## Dependency Matrix

```
T1 (pathExists) ───────► independent
T2 (test→checks) ──────► independent
T3 (split per-system) ─► after T2 (same files: flake.nix, nixos.nix)
T4 (dead mkIf) ────────► independent
T5 (merge wrappers) ───► independent
T6 (merge categories) ─► independent
T7 (empty domains) ────► independent
T8 (merge excludePkgs) ► after T4 (same file: features/default.nix)
T9 (scattered options) ► independent

Parallel batches:
  Batch A: T1 + T2 + T4 + T5 + T6 + T7 + T9
  Batch B: T3 (after T2)
  Batch C: T8 (after T4)
  Verify: T10 + T11 + T12 (after all)
```

## Must-NOT-Have
- ❌ Никаких `builtins.seq` хаков — не работают во flakes
- ❌ Не трогать `hardware/qmk/default.nix` и `hardware/video/pkgs/default.nix` — это не wrapper-ы
- ❌ Не переименовывать feature-опции — слишком большой blast radius
- ❌ Не выносить assertions в отдельный файл — нулевой выигрыш
- ❌ Не ломать `nh os switch` и `nix develop`
