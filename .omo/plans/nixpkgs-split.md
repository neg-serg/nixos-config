# Архитектурный план: разделение nixpkgs на module-форк и package-форк

## В чём проблема (одна картинка)

```
nix eval .#odin  (4.6s)
│
├── 29% времени ──→ пакетная инфраструктура 🔴
│   ├── derivation-internal.nix (3103 samples, 24%)
│   │   └── проверка атрибутов дериваций (getAttr) для Всех пакетов в pkgs
│   ├── stdenv/booter.nix (500 samples, 4%)
│   │   └── bootstrap chain для сборки gcc/glibc/stdenv
│   └── make-derivation.nix (130 samples, 1%)
│       └── валидация buildInputs/nativeBuildInputs
│
├── 41% времени ──→ модульная система 🟡
│   └── modules.nix:1149-1230 (5400 samples)
│       └── dischargeProperties → проверка типов опций, слияние значений
│
├── 21% времени ──→ инфраструктура (attrsets, lists, top-level) 🟢
│   └── базовые операции слияния, assertions, warnings
│
└── 9% времени ──→ builtins/nix internals ⚪
```

29% времени уходит на вещи которые eval'у НЕ НУЖНЫ. Они нужны только когда ты реально СОБИРАЕШЬ пакеты (nix build). Прямо сейчас eval тащит их за собой потому что nixpkgs — монолит: модули и пакеты в одном репозитории.

## Решение: разрезать монолит

Создаём ДВА форка вместо одного:

### Форк 1: `nixpkgs-modules` — для eval

Содержит **только** то что нужно `nix eval`:
- `lib/` — библиотечные функции для модульной системы (attrsets, strings, lists, modules.nix)
- `nixos/modules/` — 360 модулей которые конфиг реально импортирует
- `module-list.nix` — список модулей
- `flake.nix` — точка входа

**НЕ содержит:**
- `pkgs/` — никаких пакетов
- `stdenv/` — bootstrap chain
- `all-packages.nix` — списка пакетов
- `callPackage` — функции интроспекции

### Форк 2: `nixpkgs-packages` — для build

Содержит ВСЁ как сейчас, но **без** `nixos/modules/`. Используется когда надо реально собрать систему.

## Как это работает в конфиге

### До (сейчас)

```nix
# flake.nix
inputs.nixpkgs.url = "github:neg-serg/nixpkgs-slim/...";

outputs = { nixpkgs, ... }: {
  nixosConfigurations.odin = nixpkgs.lib.nixosSystem {
    pkgs = nixpkgs.legacyPackages.x86_64-linux;  # ← форсит ВСЕ пакеты при eval
    modules = [ ./modules/default.nix ... ];
  };
};
```

`nixpkgs.legacyPackages.x86_64-linux` тянет за собой **весь pkgs** — 25 000+ пакетов, stdenv, bootstrap, callPackage. Всё это загружается в scope `pkgs` который передаётся модулям. Даже если модуль не использует `pkgs` — он всё равно в scope.

### После (с разделением)

```nix
# flake.nix
inputs.nixpkgs-modules.url = "github:neg-serg/nixpkgs-modules";   # eval only
inputs.nixpkgs-packages.url = "github:neg-serg/nixpkgs-packages";  # build only

outputs = { nixpkgs-modules, nixpkgs-packages, ... }: {
  nixosConfigurations.odin = nixpkgs-modules.lib.nixosSystem {
    # pkgs передаётся из ПАКЕТНОГО форка, но лениво
    pkgs = nixpkgs-packages.legacyPackages.x86_64-linux;
    modules = [ ./modules/default.nix ... ];
  };
};
```

**Ключевое отличие:** `nixpkgs-modules.lib.nixosSystem` — это ОБЛЕГЧЁННАЯ версия `lib.nixosSystem`. Она:
- Не тащит derivation-ы при построении option-дерева
- Не проверяет атрибуты дериваций (getAttr) — потому что их нет
- Делает `pkgs` ленивым прокси: значения резолвятся только когда модуль реально запрашивает `pkgs.openssh`

## Детали реализации

### Шаг 1: что нужно вырезать из modules-форка

Из текущего `nixpkgs-slim` (который уже имеет 360 модулей) убираем:

```bash
# Удалить всё связанное с пакетами
rm -rf pkgs/
rm -rf stdenv/
rm -rf doc/
rm -rf maintainers/

# Из lib/ оставить только нужное модульной системе:
# lib/attrsets.nix, lib/strings.nix, lib/lists.nix, lib/trivial.nix
# lib/modules.nix, lib/options.nix, lib/types.nix, lib/debug.nix
# lib/default.nix (пересобрать без пакетных зависимостей)
# Остальное в lib/ можно оставить (не форсится пока не нужно)

# Из flake.nix убрать:
# - packages output
# - devShells output
# - formatter output
# - legacyPackages (ссылается на pkgs)
# Оставить только:
# - lib output
# - nixosModules (если есть)
```

### Шаг 2: проблема `default = pkgs.X` в опциях

Сейчас многие модули nixpkgs содержат:

```nix
options.services.openssh.package = mkOption {
  type = types.package;
  default = pkgs.openssh;  // ← нужен pkgs
};
```

Без `pkgs` модуль не скомпилируется. Решение — **отложенная инициализация**:

```nix
# Вариант А: убрать default, оставить только defaultText
options.services.openssh.package = mkOption {
  type = types.package;
  defaultText = "pkgs.openssh";
  # default — не указываем, будет вычислен позже
};

# Вариант Б: сделать pkgs ленивым прокси
# В flake.nix:
specialArgs = {
  pkgs = builtins.mapAttrs (name: _: throw "lazy pkgs not resolved") (builtins.functionArgs (_: {}));
};
# НЕ будет работать — functionArgs от {} возвращает {} 

# Вариант В: вычислять default в момент первого обращения
# Через lib.mkDefault с отложенным thunk-ом
options.services.openssh.package = mkOption {
  type = types.package;
  default = lib.mkDefault (builtins.trace "lazy" pkgs.openssh);
  # mkDefault создаёт отложенное значение
};
```

Вариант В — самый реальный. `lib.mkDefault` создаёт thunk который не форсится до момента когда опция реально читается. При eval-е `nix eval .#name` опции не читаются глубоко — только surface-level проверка.

### Шаг 3: что даёт ускорение (почему)

Сейчас `derivation-internal.nix:getAttr` берёт 24% времени. Это происходит потому что каждая опция типа `types.package` с `default = pkgs.X` заставляет nix проверять атрибуты деривации `pkgs.X`:
- `pkgs.X.name` — строка
- `pkgs.X.drvPath` — путь
- `pkgs.X.outputs` — список
- `pkgs.X.meta` — метаданные
- И ещё ~20 атрибутов

Каждый `getAttr` — это поиск в хеш-таблице деривации. 3103 сэмпла × ~30 атрибутов = ~90 000 обращений к деривациям за eval. 

С modules-форком:
- `pkgs` либо нет совсем (derivations не создаются) = 0 getAttr
- Либо `pkgs` ленивый = getAttr только для реально используемых пакетов (~150 вместо 25 000)

### Шаг 4: memory savings

Без пакетов память падает с 1.23 GB до ~0.5 GB (нет дерева дериваций в памяти). Это ускоряет GC и общий eval.

## Ожидаемый результат

```
Сейчас:   4.6s, 1.23 GB
После:    ~2.8-3.3s, ~0.5 GB
Экономия: ~30-40% по времени, ~60% по памяти
```

## Риски

1. **Ломается nixos-rebuild build phase.** Если modules-форк ломает `pkgs` в scope настолько что `nixosSystem` не может построить конфиг для БИЛДА — нужен fallback на packages-форк. Решение: `nh os switch` всегда использует packages-форк; eval-only команды используют modules-форк.

2. **Некоторые модули используют `pkgs` не в `default` а в `config`.** Например `config.environment.systemPackages = [ pkgs.foo pkgs.bar ];`. Это build-фаза — здесь pkgs нужен. Но модуль будет загружаться и в eval-фазе. Решение: обернуть в `lib.mkIf` с условием которое проверяет что pkgs доступен.

3. **lib/default.nix ссылается на пакетные функции.** Сейчас `lib/default.nix` ре-экспортирует всё из `lib/` + некоторые вещи из `pkgs/`. Нужно почистить чтобы осталось только модульное.

## План действий

### Шаг 1: Создать nixpkgs-modules репозиторий
- Форкнуть nixpkgs-slim (уже 360 модулей)
- Удалить pkgs/, stdenv/, doc/, maintainers/
- Почистить lib/default.nix
- Почистить flake.nix

### Шаг 2: Починить default = pkgs.X в модулях
- Пройти по ВСЕМ module declaration и найти `default = pkgs.X`
- Заменить на `default = lib.mkDefault (lazyPkgs.X)` где `lazyPkgs` — отложенный доступ
- Протестировать что модули компилируются без полного pkgs

### Шаг 3: Настроить flake.nix конфига
- Добавить inputs.nixpkgs-modules и inputs.nixpkgs-packages
- `nix eval` использует modules-форк
- `nh os switch` использует packages-форк

### Шаг 4: Бенчмарк до/после
- Сравнить eval время и память
