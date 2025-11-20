# Обзор репозитория

Репозиторий объединяет конфигурацию NixOS и историческую конфигурацию Home Manager (каталог
`home/`). Системные модули — единственный источник истины: пакеты и сервисы подключаются через
`modules/`, а Home Manager остаётся доступным для автономных/WSL‑сценариев и разработки. Все
инструкции сведены в этом файле, чтобы больше не держать отдельные README для системной и
пользовательской частей.

## Структура дерева

- `modules/`, `packages/`, `docs/`, `hosts/` — системные модули, оверлеи и документация.
- `home/` — flake Home Manager для автономной работы.
- `templates/` — заготовки проектов (Rust crane, Python CLI, shell app).
- `docs/manual/manual.*.md` — канонические руководства.

## Быстрый старт (система)

- Переключение: `sudo nixos-rebuild switch --flake /etc/nixos#<host>`
- Генерация опций: `nix run .#gen-options`
- Форматирование/линт/проверки: `just fmt`, `just lint`, `just check`
- Опционально: `just hooks-enable` для включения git-hooks

## Быстрый старт (Home Manager)

### Предпосылки

1. Установите Nix и включите flakes (`experimental-features = nix-command flakes`).
2. Инициализируйте Home Manager через flakes:
   `nix run home-manager/master -- init --switch`
3. Рекомендуемый helper: `nix profile install nixpkgs#just`

### Клонирование и переключение профилей

- Для автономных сценариев клонируйте `~/.dotfiles` (или используйте `/etc/nixos/home` в объединённом дереве).
- Переключение профилей:
  - Полный: `just hm-neg` (`home-manager switch --flake .#neg`)
- Сборка без переключения: `just hm-build`
- На хостах с общим репозиторием используйте `sudo nixos-rebuild switch --flake /etc/nixos#<host>`;
  `hm-*` оставлены для standalone/dev окружений.

### Профили и feature flags

- Главный переключатель: `features.profile = "full" | "lite"` (lite отключает GUI/media/dev по умолчанию).
- Опции описаны в `home/modules/features.nix`; краткая сводка — в `OPTIONS.md`.
- Ключевые флаги:
  - GUI (`features.gui.*`), Web (`features.web.*`), Secrets (`features.secrets.enable`)
  - Dev стеки (`features.dev.*`, `features.dev.openxr.*`, `features.dev.unreal.*`)
  - Media/Torrent (`features.media.*`, `features.torrent.enable`)
  - Finance (`features.finance.tws.enable`), Fun (`features.fun.enable`)
  - Исключение пакетов по pname: `features.excludePkgs`

Показать плоский список фич: `just show-features` (с `ONLY_TRUE=1` выводит только `true`).

### Повседневные команды

- Форматирование: `just fmt`
- Проверки: `just check`
- Линт: `just lint`
- Переключение HM: `just hm-neg` / `just hm-lite`
- Статус/логи: `just hm-status` (`systemctl --user --failed` + хвост журнала)

### Секреты (sops-nix / vaultix)

- Секреты лежат в `secrets/` и подключаются через sops-nix; гайд по переходу на vaultix:
  `docs/vaultix-migration.ru.md`.
- Age-ключи: `~/.config/sops/age/keys.txt`.
- Токен Cachix находится в `secrets/cachix.env` (sops).

### Сервисы systemd (user)

- Используйте `config.lib.neg.systemdUser.mkUnitFromPresets` для назначения таргетов
  (`graphical`, `netOnline`, `defaultWanted`, `timers`, `dbusSocket`, `socketsTarget`).
- Управление: `systemctl --user start|stop|status <unit>`, логи:
  `journalctl --user -u <unit>`.

### Hyprland и GUI

- Автоперезагрузка Hyprland отключена; перезапускайте хоткеем.
- Конфиги Hypr разбиты на файлы в `modules/user/gui/hypr/conf/*` и линкуются HM.
- `~/.local/bin/rofi` задаёт дефолтные флаги, автопринятие и поиск тем в XDG путях; отключайте
  автопринятие флагом `-no-auto-select`.
- Индикатор раскладки в Quickshell слушает `keyboard-layout` Hyprland, предпочитает устройство с
  `main: true` и переключает `hyprctl switchxkblayout current next`.
- Floorp: навбар оставлен сверху, отключены телеметрия и мусор на вкладке «Новая».
- `swayimg-first` ставится как `~/.local/bin/swayimg`, а правила Hyprland задают float/позицию.

### Заметки для разработчиков

- Формат коммитов: `[scope] message` (хуки `.githooks/commit-msg` могут проверять автоматически).
- Hyprland/порталы закреплены через flake inputs; см. разделы ниже для политики обновлений.

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

- Источник истины: `inputs.hyprland` (композитор) закреплён на Hyprland v0.52.1, а `inputs.hy3` (плагин) продолжает указывать на `hl0.51.0`; конкретные коммиты фиксирует `flake.lock`.
- Оверлей NixOS переназначает `pkgs.hyprland`, `pkgs.xdg-desktop-portal-hyprland` и `pkgs.hyprlandPlugins.hy3` на эти инпуты, так что в модулях достаточно использовать `pkgs.*`.
- Связанные инпуты синхронизируются через `follows` (`hyprland-protocols`, `xdg-desktop-portal-hyprland` и др.), дополнительных ручных подключений портала не нужно.
- Не добавляйте `xdg-desktop-portal-hyprland` в `xdg.portal.extraPortals` — сервис уже приезжает через `portalPackage`.

Как обновить Hyprland (и hy3):

1) Обновить пины: `nix flake update hyprland hy3` (остальные hyprland‑инпуты подтянутся автоматически).
2) Пересобрать систему: `sudo nixos-rebuild switch --flake /etc/nixos#<host>`.

Опционально: при включённом `system.autoUpgrade` добавьте `--update-input hyprland --update-input hy3` при осознанном переходе на следующий релиз Hyprland. Обычно обновляем вручную, чтобы контролировать ABI.

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


---

# AGENTS: советы и грабли при интеграции мониторинга и Nextcloud

В репозитории используется кастомная цель `post-boot.target`, Nextcloud через PHP‑FPM за Caddy, и экспортеры Prometheus. Ниже — основные грабли и рабочие фиксы, чтобы не наступать повторно.

Post‑Boot Systemd Target
- Не добавляйте `After=graphical.target` в сам `post-boot.target`; `graphical.target` уже хочет `post-boot.target`. Добавление `After=graphical.target` на target создаёт цикл упорядочивания.
- Перенося сервисы на post‑boot, избегайте безусловного `After=graphical.target` в хелпере, который цепляет юниты к `post-boot.target`. Пусть target будет wanted графическим таргетом, а конкретные `After=` добавляйте только по необходимости (никогда не на сам target).

Профиль Wi‑Fi (iwd)
- Базовый сетевой модуль ставит тулзы iwd, но держит `networking.wireless.iwd.enable = false`, чтобы проводные хосты не поднимали сервис.
- Если на хосте нужен Wi‑Fi, включите `profiles.network.wifi.enable = true;` (например, в `hosts/<имя>/networking.nix`) вместо ручного `lib.mkForce`.

Prometheus PHP‑FPM Exporter + пул Nextcloud
- Доступ к сокету: экспортер читает `unix:///run/phpfpm/nextcloud.sock;/status`. Убедитесь, что сокет пула PHP‑FPM доступен на чтение группе общего веб‑пула, и экспортер входит в неё:
  - `services.phpfpm.pools.nextcloud.settings`: `"listen.group" = "nginx";`, `"listen.mode" = "0660"`.
  - Добавьте пользователей `caddy` и `prometheus` в группу `nginx` через `users.users.<name>.extraGroups = [ "nginx" ];`.
- Песочница юнита: апстрим‑юнит экспортера может запрещать UNIX‑сокеты через `RestrictAddressFamilies`.
  - Разрешите AF_UNIX: `RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];`.
  - Дайте юниту доступ к группе сокета: `SupplementaryGroups = [ "nginx" ];`.
- DynamicUser vs. постоянный пользователь: апстрим может использовать `DynamicUser=true` и `Group=php-fpm-exporter`. Чтобы экспортер наследовал статическое членство в группах, переопределите с большим приоритетом:
  - `DynamicUser = lib.mkForce false; User = lib.mkForce "prometheus"; Group = lib.mkForce "prometheus";`.
- Порядок запуска: стартовать экспортер после того, как поднят пул Nextcloud PHP‑FPM, чтобы избежать начальных ошибок подключения:
  - `after = [ "phpfpm-nextcloud.service" "phpfpm.service" "nextcloud-setup.service" ];`
  - `wants = [ "phpfpm-nextcloud.service" ];`

Экстренная безопасность switch
- Если при отладке экспортер блокирует активацию, временно отключите его, чтобы разблокировать `switch`: `services.prometheus.exporters."php-fpm".enable = false;` и включите обратно после фикса прав/порядка.

Типовые ошибки
- Неправильное место для extraGroups: внутри `users = { ... }` задавайте `users.caddy.extraGroups = [ "nginx" ];` и `users.prometheus.extraGroups = [ "nginx" ];` (это маппится на `users.users.<name>.extraGroups`). Не пишите повторно `users.users.caddy` внутри `users = { ... }` — получится `users.users.users.caddy` и сломает оценку.
- Двойное включение прокси: не включайте одновременно `nextcloud.nginxProxy` и `nextcloud.caddyProxy` (есть assertion, но помнить полезно).
