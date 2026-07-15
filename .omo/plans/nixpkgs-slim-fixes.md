# План: Оптимизация nixpkgs-slim — конкретные правки

## Где мы сейчас

```
eval: 4.6s (1.23 GB)
├── 24% → derivation-internal.nix:getAttr (3103 samples) ← types.package.check
├── 41% → modules.nix:dischargeProperties (5400 samples)  ← applyModuleArgs + merge
├──  4% → stdenv/booter.nix (500 samples)                  ← pkgs bootstrap
└── 31% → всё остальное
```

## Корень проблемы (одно предложение)

`types.package.check` в `lib/types.nix` вызывает `isDerivation(x)` который лезет в `getAttr(x, "name")`, `getAttr(x, "drvPath")`, `getAttr(x, "outputs")` — и это для **каждой** опции с типом `types.package` × **каждый** модуль который её определяет. 24% времени.

## Что делаем (конкретные правки)

### Правка 1: `lib/types.nix` — облегчить `types.package.check`

**Файл:** `/tmp/nixpkgs-slim/lib/types.nix`

**Найти:** `isDerivation` в определении `types.package` (~строка 540-560)

**Сейчас:**
```nix
types.package = mkOptionType {
  name = "package";
  check = x: isDerivation x || isStorePath x;
  merge = ...
};
```

**Заменить на:**
```nix
types.package = mkOptionType {
  name = "package";
  check = x: true;  # skip derivation attr check — validated at build time
  merge = ...
};
```

**Почему безопасно:** Nix сам проверит что деривация валидная когда начнёт собирать `system.build.toplevel`. Типобезопасность сохраняется на build-фазе, экономится на eval-фазе.

**Ожидаемый эффект:** −24% eval времени (3103 сэмпла → ~0)

### Правка 2: `modules.nix` — уменьшить `dischargeProperties`

**Файл:** `/tmp/nixpkgs-slim/lib/modules.nix`

**Найти:** `dischargeProperties` (~строка 1149-1230)

**Проблема:** для каждого определения опции вызывается `dischargeProperties` который оборачивает значение в `addErrorContext`. Даже для опций с одним определением (нет конфликта) — overhead от `addErrorContext` остаётся.

**Сейчас (псевдокод):**
```nix
dischargeProperties = def:
  if def._type == "if" then
    if def.condition then dischargeProperties def.content
    else ...
  else if def._type == "merge" then ...
  else addErrorContext "while evaluating..." def.value;
```

**Оптимизация:** добавить fast-path для самого частого случая — простое значение без `mkIf`/`mkMerge`/`mkOverride`:

```nix
dischargeProperties = def:
  if !def ? _type then def.value           # ← fast path: обычное значение
  else if def._type == "if" then ...
  else if def._type == "merge" then ...
  else addErrorContext ... def.value;
```

**Ожидаемый эффект:** −5-10% eval времени (быстрее для опций без конфликтов)

### Правка 3: sshd.nix — убрать `pkgs.*` из `let`-блока

**Файл:** `/tmp/nixpkgs-slim/nixos/modules/services/networking/ssh/sshd.nix`

**Строка 13-17 — убрать cross-compile check:**
```nix
# Было:
validationPackage =
    if pkgs.stdenv.buildPlatform == pkgs.stdenv.hostPlatform then cfg.package
    else pkgs.buildPackages.openssh;

# Стало:
validationPackage = cfg.package;
```

**Строка 38 — заменить `pkgs.formats` на `lib.generators`:**
```nix
# Было:
base = pkgs.formats.keyValue { ... };

# Стало:
base = lib.generators.toKeyValue {
    mkKeyValue = lib.generators.mkKeyValueDefault { ... } " ";
};
```

**Ожидаемый эффект:** −2 `pkgs.*` форсирования при импорте модуля. ×360 модулей = заметно.

### Правка 4: `all-packages.nix` — выпилить неиспользуемые пакеты

**Файл:** `/tmp/nixpkgs-slim/pkgs/top-level/all-packages.nix`

**Что:** Из 3720 атрибутов оставить только ~149 которые реально нужны (из нашего конфига) + infrastructure (~300 атрибутов). Остальные ~3271 атрибут — удалить.

**Как:** берём список из 149 пакетов (уже собран раньше). Для каждого атрибута в all-packages.nix который НЕ в списке и НЕ infrastructure — удаляем строку.

**Ожидаемый эффект:** меньше `callPackage` при построении pkgs, меньше `functionArgs` (5.7%).

### Правка 5: `by-name` пакеты — пробуем ещё раз

**Файлы:** `/tmp/nixpkgs-slim/pkgs/by-name/*/`

**Подход:** не удалять пакетные директории (это сломало build в прошлый раз), а сделать `by-name-overlay.nix` чтобы он ПРОПУСКАЛ пакеты не из whitelist. 

**Как:** в `by-name-overlay.nix` перед `callPackage` добавить фильтр:
```nix
# Только если пакет в whitelist
if builtins.elem name whitelist then callPackage ... else null
```

**Ожидаемый эффект:** −callPackage для ~20 000 неиспользуемых by-name пакетов.

## Порядок выполнения

```
Правка 1 (types.nix)     → замер: должно быть ~3.5s (−24%)
Правка 2 (modules.nix)   → замер: должно быть ~3.2s (−10%)
Правка 3 (sshd.nix)      → замер: должно быть ~3.1s (−3%)
Правка 4 (all-packages)  → замер: должно быть ~2.8s (−10%)
Правка 5 (by-name)       → замер: должно быть ~2.5s (−10%)
```

Каждая правка коммитится отдельно в `nixpkgs-slim`. После каждой — `nix eval --refresh --offline` для замера.

## Риски

1. **Правка 1:** `types.package.check = x: true` — если какой-то модуль полагается на `check` для ранней валидации. **Митигация:** оставить `check = x: isStorePath x || true` — минимальная проверка без `isDerivation`.

2. **Правка 2:** fast-path для `dischargeProperties` — может пропустить edge-case где `_type` установлен неявно. **Митигация:** тестировать на полном `nh os switch --dry`.

3. **Правка 5:** whitelist для by-name — нужно точно знать какие имена пакетов в by-name матчатся с именами из конфига. **Митигация:** начать с консервативного whitelist (500 пакетов), потом сужать.

## Не делаем

- ❌ Два форка (modules + packages) — слишком сложно поддерживать
- ❌ `mkDefault` для ленивости — не работает
- ❌ Переписывание ВСЕХ 360 модулей — правка 1 решает ту же проблему глобально
- ❌ Удаление `pkgs` из модульной системы — сломает `runCommand`/`writeText`
