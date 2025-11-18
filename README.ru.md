# Документация (русская версия)

Этот файл содержит русские разделы основной документации. Англоязычная основная версия: `README.md`.

## RNNoise виртуальный микрофон (PipeWire)

- Виртуальный микрофон с шумоподавлением RNNoise через PipeWire filter‑chain.
- По умолчанию включён глобально; на нужных хостах можно отключить.

Пример:

```nix
{
  # Глобально (в модуле по умолчанию true)
  hardware.audio.rnnoise.enable = true;

  # Переопределение на хосте (например, hosts/telfir/services.nix)
  hardware.audio.rnnoise.enable = false;
}
```

Заметки:
- Пользовательский сервис при входе в систему автоматически делает RNNoise‑источник источником по умолчанию (если включено).
- Источник можно выбрать вручную в настройках окружения рабочего стола.

## Defaults, Overrides и mkForce Policy

- Модули задают значения через `mkDefault` (их легко переопределить на хосте простым присваиванием):
  - Примеры: `services.timesyncd.enable`, `zramSwap.enable`, `boot.lanzaboote.enable`, `nix.gc.automatic`, `nix.optimise.automatic`, `nix.settings.auto-optimise-store`, `boot.kernelPackages` (как `mkDefault`).
- На хостах предпочитайте обычные присваивания:
  - Булевы флаги: `foo.enable = false;`
  - Уникальные опции (например, `boot.kernelPackages`): просто `boot.kernelPackages = pkgs.linuxPackages_latest;`
- Используйте `lib.mkForce` только когда нужно зачистить/перебить слияния или спорные уникальные значения:
  - Списки: чтобы явно очистить ранее добавленные элементы — `someListOption = lib.mkForce [];`
  - Редкие конфликты уникальных опций от разных модулей.

Примеры

```nix
# VM: принудительно отключить тяжёлые сервисы из ролей
{ lib, ... }: {
  profiles.services = {
    nextcloud.enable = false;
    adguardhome.enable = false;
    unbound.enable = false;
  };

  # VM: упростить набор ядра
  boot.kernelPackages = pkgs.linuxPackages_latest;
}

# Паттерн модуля (без mkForce):
{ lib, config, ... }: let
  cfg = config.servicesProfiles.example;
in {
  options.servicesProfiles.example.enable = lib.mkEnableOption "Example service profile";
  config = lib.mkIf cfg.enable {
    services.example.enable = lib.mkDefault true; # host может переопределить
  };
}
```

## Паттерн модулей и хелперы опций

- Единый паттерн:
  - `options.<path>.*` объявляет опции;
  - `let cfg = config.<path>; in` — локальная ссылка;
  - `config = lib.mkIf cfg.enable { … }` включает конфиг по флагу.
- Хелперы в `lib/opts.nix`:
  - Примитивы: `mkBoolOpt`, `mkStrOpt`, `mkIntOpt`, `mkPathOpt`;
  - Составные: `mkListOpt elemType`, `mkEnumOpt values`;
  - Унифицированные описания через `mkDoc`.

Пример использования в модуле:

```nix
{ lib, config, ... }: let
  opts = (import ../lib { inherit lib; }).opts;
  cfg = config.example.feature;
in {
  options.example.feature = {
    enable = lib.mkEnableOption "Enable example feature";
    mode = opts.mkEnumOpt ["fast" "safe"] {
      description = "Operating mode";
      default = "fast";
    };
  };

  config = lib.mkIf cfg.enable {
    services.example.enable = true;
  };
}
```

## Игры: заметки

- Proton‑GE часто улучшает производительность/совместимость (установлен). При регрессиях вернитесь на Valve Proton.
- MangoHud: `MANGOHUD=1`. Ограничение FPS: `MANGOHUD=1 MANGOHUD_CONFIG=fps_limit=237 game-run %command%`. По умолчанию конфиг: `etc/xdg/MangoHud/MangoHud.conf`.
- Mesa/AMD:
  - Vulkan ICD по умолчанию RADV (`AMD_VULKAN_ICD=RADV`); переключайте только при необходимости.
  - Для старых GL‑тайтлов помогает `MESA_GLTHREAD=true`.

### Troubleshooting стуттеров

- Убедиться, что VRR активен (OSD монитора/`gamescope --verbose`).
- Проверить, что игра действительно в Gamescope (не встраиваемый лаунчер вне VRR).
- Прогреть шейдер‑кеш (Steam Shader Pre‑Caching включён) — первые минуты возможны микрофризы.
- Если подвисания при автосохранениях/дисковом I/O — проверьте, что игра не установлена на перегруженный диск и что нет фонового индексирования.

### Полезные команды

- Показать текущий CPU‑набор процесса: `grep Cpus_allowed_list /proc/<pid>/status`.
- Скопировать пер‑игровой запуск: `game-run %command%` (Steam), `game-run <path>` (вне Steam).

## Мониторинг DNS‑резолвера

- Unbound + Prometheus + Grafana для оценивания качества DNS (задержки, DNSSEC‑валидация, кэш‑хиты): см. `docs/unbound-metrics.ru.md`.

## Мониторинг Nextcloud

- Blackbox‑проба `https://telfir/status.php` и график задержки; опционально — экспортер PHP‑FPM для состояния пула: см. `docs/nextcloud-monitoring.ru.md`.

## Grafana: egress и жёсткое ограничение (TODO)

- Возможные источники внешнего трафика и политика его блокировки/разрешения: см. `docs/grafana-egress-todo.ru.md`.

## Политика «тихой» оценки (Evaluation Noise Policy)

- Не допускаем предупреждений/трейсов во время оценки конфигурации — сборки и переключения должны быть «тихими».
- В модулях не используем `warnings = [ … ]`, `builtins.trace`, `lib.warn`.
- Если фича/пакет недоступны — тихо пропускаем или защищаем флагом; поведение документируем в README модулей, а не сообщениями во время оценки.
- Ассерты используем только для действительно фатальных конфигураций, которые сломают систему; формулируем кратко.

## Hyprland: единый источник и обновления

- Источник истины: `inputs.hyprland` закреплён на стабильном теге (см. `flake.nix`).
- Зависимости синхронизируются через `follows` (раскладка v0.52):
  - `hyprland-protocols` → `hyprland/hyprland-protocols`
  - `xdg-desktop-portal-hyprland` → `hyprland/xdph`
- Использование в модулях:
  - `programs.hyprland.package = inputs.hyprland.packages.<system>.hyprland`
  - `programs.hyprland.portalPackage = inputs.xdg-desktop-portal-hyprland.packages.<system>.xdg-desktop-portal-hyprland`
  - Не добавляйте `xdg-desktop-portal-hyprland` в `xdg.portal.extraPortals` (иначе дубль юнита) — он приходит через `portalPackage`.

Как обновить Hyprland (и связанные зависимости):

1) Изменить `inputs.hyprland.url` в `flake.nix` (например, на новый релиз).
2) Обновить лок: `nix flake lock --update-input hyprland`.
3) Пересобрать систему: `sudo nixos-rebuild switch --flake /etc/nixos#<host>`.

Опционально: при включённом `system.autoUpgrade` можно добавлять `--update-input hyprland` для авто‑подтягивания обновлений, но чаще обновляем вручную ради совместимости.

## Роли и профили

- Роли: включают наборы через `modules/roles/{workstation,homelab,media}.nix`.
  - `roles.workstation.enable = true;` → рабочая станция (профиль производительности, SSH, Avahi, Syncthing).
  - `roles.homelab.enable = true;` → селф‑хостинг (профиль безопасности, DNS, SSH, Syncthing, MPD, Navidrome, Wakapi, Nextcloud).
  - `roles.media.enable = true;` → медиа‑серверы (Jellyfin, Navidrome, MPD, Avahi, SSH).
- Профили: фичи под `modules/system/profiles/`.
  - `profiles.performance.enable` и `profiles.security.enable` переключаются ролями; можно переопределять на хосте.
- Профили сервисов: `profiles.services.<name>.enable` (алиас к `servicesProfiles.<name>.enable`).
  - Роли ставят `mkDefault true`; на хосте можно просто выключить `false` (без mkForce).
- Хост‑специфика: храните конкретные настройки под `hosts/<host>/*.nix`.

Пример (хост):

```nix
{ lib, ... }: {
  roles = {
    workstation.enable = true;
    homelab.enable = true;
  };

  # Отключаем тяжёлые сервисы для VM/минимальных сборок
  profiles.services = {
    nextcloud.enable = false;
    adguardhome.enable = false;
  };

  # Хост‑специфичный Syncthing
  services.syncthing = {
    overrideDevices = true;
    overrideFolders = true;
    settings.devices."phone" = { id = "AAAA-BBBB-..."; };
  };
}
```

## Ядро: PREEMPT_RT

- Переключатель: `profiles.performance.preemptRt.enable = true;`
- Режим: `profiles.performance.preemptRt.mode = "auto" | "in-tree" | "rt";`
  - `auto`: включает in-tree `CONFIG_PREEMPT_RT` на ядрах ≥ 6.12, иначе переключает пакет на `linuxPackages_rt`.
  - `in-tree`: принудительно включает `CONFIG_PREEMPT_RT` в текущем пакете ядра (без смены пакета).
  - `rt`: явно переключает пакет ядра на `pkgs.linuxPackages_rt`.

Примечание: внештатные модули (например, `amneziawg`) подтягиваются из выбранного `boot.kernelPackages`, когда доступны.

## Отладка/профайлинг (опционально)

- Профилирование аллокаций памяти (6.10+): `profiles.debug.memAllocProfiling.{enable,compileSupport,enabledByDefault,debugChecks}`.
- perf data‑type профайлинг (6.8+): `profiles.debug.perfDataType.{enable,installTools,enableKernelBtf}`.
- sched_ext (6.12+): `profiles.debug.schedExt.{enable,installTools,enableKernelBtf}`.
  - Включение некоторых опций может пересобирать ядро (требуются `CONFIG_*`).

## Охлаждение / Fan Control (тихий профиль)

- Включение датчиков и тихой кривой вентиляторов: `hardware.cooling.*` (модуль: `modules/hardware/cooling.nix`).
- Для типичных плат ASUS/Nuvoton модуль грузит `nct6775` и генерирует `/etc/fancontrol` на старте.
- Опционально: добавить вентилятор GPU в тот же профиль (`hardware.cooling.gpuFancontrol.enable = true;`).

Пример (тихо и безопасно):

```nix
{
  hardware.cooling = {
    enable = true;
    autoFancontrol.enable = true;  # автогенерация тихой кривой
    gpuFancontrol.enable = true;   # включить AMDGPU pwm1 с тихой кривой
    # Доп. параметры (дефолты показаны):
    # autoFancontrol.minTemp = 35;  # °C — старт разгона
    # autoFancontrol.maxTemp = 75;  # °C — максимум
    # autoFancontrol.minPwm  = 70;  # 0–255, избегаем срыва вращения
    # autoFancontrol.maxPwm  = 255; # 0–255
    # autoFancontrol.hysteresis = 3;  # °C
    # autoFancontrol.interval  = 2;   # сек
    # autoFancontrol.allowStop = false;      # полный стоп ниже порога
    # autoFancontrol.gpuPwmChannels = [ ];   # PWM‑каналы (напр., [2 3]) по температуре GPU
  };
}
```

Заметки:
- Генератор ведёт все PWM матплаты (nct6775) по температуре CPU (`k10temp`).
- При `gpuFancontrol.enable = true` вентилятор GPU (amdgpu pwm1) ведётся по температуре GPU (желательно «junction» при наличии).
- Если `/etc/fancontrol` уже есть, он разово бэкапится в `/etc/fancontrol.backup` и заменяется ссылкой на `/etc/fancontrol.auto`.
- Вентиляторы GPU обычно управляются драйвером; модуль целит только PWM матплаты.
  - Исключение: когда `gpuFancontrol.enable = true`, переводим `pwm1_enable` в ручной режим и управление берёт fancontrol.

### Тест возможности полной остановки вентилятора

- Утилита: `fan-stop-capability-test` определяет, какие PWM‑каналы матплаты могут полностью остановиться на 0%.
- Безопасность по умолчанию: пропускает CPU/PUMP/AIO; после пробы возвращает исходные значения.
- Примеры:
  - Только список: `sudo fan-stop-capability-test --list`
  - Тест корпусных: `sudo fan-stop-capability-test`
  - Включая CPU/PUMP (на свой риск): `sudo fan-stop-capability-test --include-cpu`
- Опции: `--device <hwmonN|nct6798>`, `--wait <sec>` (по умолчанию 6), `--threshold <rpm>` (по умолчанию 50).
- Примечание: для точности остановите `fancontrol` на время теста — `sudo systemctl stop fancontrol`.

## GPU CoreCtrl (Undervolt/Power‑Limit)

- Опционально (по умолчанию выключено): `hardware.gpu.corectrl.enable = false;`
- При включении устанавливается CoreCtrl и правило polkit, позволяющее членам выбранной группы (`wheel` по умолчанию) использовать helper.
- Опционально: `hardware.gpu.corectrl.ppfeaturemask = "0xffffffff";` — разблокирует расширенные OC/UV на некоторых AMD GPU.

Пример:

```nix
{
  hardware.gpu.corectrl = {
    enable = true;            # по умолчанию выключено
    group = "wheel";          # кто может настраивать
    # ppfeaturemask = "0xffffffff"; # опционально, если требуется для вашей GPU
  };
}
```

## AutoFDO (семпловые профили для PGO)

Включение инструментов и опциональных обёрток компиляторов:

```nix
{ lib, ... }: {
  # Установить инструменты AutoFDO
  dev.gcc.autofdo.enable = true;

  # Обёртки GCC `gcc-afdo` и `g++-afdo`
  # автоматически добавляют -fauto-profile=<path>
  dev.gcc.autofdo.gccProfile = "/var/lib/afdo/myprofile.afdo";

  # Обёртки Clang `clang-afdo` и `clang++-afdo`
  # автоматически добавляют -fprofile-sample-use=<path>
  # dev.gcc.autofdo.clangProfile = "/var/lib/afdo/llvm.prof";
}
```

Использование:

- GCC: `gcc-afdo main.c -O3 -o app`
- Clang: `clang-afdo main.c -O3 -o app`
