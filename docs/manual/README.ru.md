# Обзор репозитория

Репозиторий содержит полную конфигурацию NixOS с управлением пользовательской частью через nix-maid.
Пакеты и сервисы подключаются через `modules/`, пользовательская конфигурация — в
`modules/user/nix-maid/`. Все инструкции сведены в этом файле.

## Структура дерева

- `modules/`, `packages/`, `docs/`, `hosts/` — системные модули, оверлеи и документация
  (`docs/manual`, `docs/howto`, `docs/runbooks`).
- `files/` — статические конфигурационные файлы, линкуемые в домашние директории через nix-maid.
- `templates/` — заготовки проектов (Rust crane, Python CLI, shell app).
- `docs/manual/manual.*.md` — канонические руководства.

## Быстрый старт (система)

- Переключение: `sudo nixos-rebuild switch --flake /etc/nixos#<host>`
- Генерация опций: `nix run .#gen-options`
- Форматирование/линт/проверки: `just fmt`, `just lint`, `just check`
- Опционально: `just hooks-enable` для включения git-hooks

## Быстрый старт (пользовательская конфигурация)

### Предпосылки

1. Установите Nix и включите flakes (`experimental-features = nix-command flakes`).
1. Пользовательская конфигурация управляется через модули nix-maid в `modules/user/nix-maid/`.
1. Рекомендуемый helper: `nix profile install nixpkgs#just`

### Применение конфигурации

- Пользовательская конфигурация применяется автоматически при `nixos-rebuild switch`.
- Сборка без переключения: `nixos-rebuild build --flake .#<host>`.

### Профили и feature flags

- Главный переключатель: `features.profile = "full" | "lite"` (lite отключает GUI/media/dev по
  умолчанию).
- Опции описаны в `modules/features.nix`; краткая сводка — в `OPTIONS.md`.
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
- Пересборка: `sudo nixos-rebuild switch --flake .#<host>`

### Секреты (sops-nix / vaultix)

- Секреты лежат в `secrets/` и подключаются через sops-nix; гайд по переходу на vaultix:
  `docs/runbooks/vaultix-migration.ru.md`.
- Age-ключи: `~/.config/sops/age/keys.txt`.
- Токен Cachix находится в `secrets/cachix.env` (sops).

### Сервисы systemd (user)

- Используйте `config.lib.neg.systemdUser.mkUnitFromPresets` для назначения таргетов (`graphical`,
  `netOnline`, `defaultWanted`, `timers`, `dbusSocket`, `socketsTarget`).
- Управление: `systemctl --user start|stop|status <unit>`, логи: `journalctl --user -u <unit>`.

## WireGuard VPN (host / user)

- Хостовый on-demand WireGuard‑туннель для `telfir` настроен в `hosts/telfir/services.nix` как
  `systemd.services."wg-quick-vpn-telfir"`, который использует wg‑quick‑конфиг из sops‑секрета
  `sops.secrets."wireguard/telfir-wg-quick"`.
- Секретный файл ожидается в репозитории как `secrets/telfir-wireguard-wg-quick.sops` (формат
  `binary`, содержимое — обычный wg‑quick конфиг с `[Interface]/[Peer]`, DNS и MTU).
- Туннель не поднимается по умолчанию; включение/выключение:
  `sudo systemctl start wg-quick-vpn-telfir` / `sudo systemctl stop wg-quick-vpn-telfir`.
- DNS из секции `DNS = …` применяется только при активном туннеле за счёт wg‑quick; убедитесь, что
  на хосте установлены необходимые утилиты (`wireguard-tools` уже добавлен в
  `modules/system/net/vpn/pkgs.nix`).

### Создание sops‑секрета для WireGuard

- Подготовьте временный plaintext‑файл (НЕ коммитить в git), например
  `secrets/telfir-wireguard-wg-quick.conf` с содержимым: `[Interface]`, `PrivateKey = …`,
  `Address = 10.0.0.2/32`, `DNS = 1.1.1.1, 1.0.0.1`, `MTU = 1420` и соответствующим `[Peer]` блоком.
- Зашифруйте его через sops в бинарный файл, привязанный к age‑ключам из
  `~/.config/sops/age/keys.txt`:
  `sops -e secrets/telfir-wireguard-wg-quick.conf > secrets/telfir-wireguard-wg-quick.sops`.
- Удалите plaintext: `rm -f secrets/telfir-wireguard-wg-quick.conf`.
- После этого `nixos-rebuild switch --flake .#telfir` подхватит секрет, создаст файл в
  `/run/secrets` и системный юнит `wg-quick-vpn-telfir.service`.

### Идеи для user-level WireGuard

- Для туннелей только для одного пользователя можно применять тот же подход, но через Home Manager и
  `systemd.user.services`, где sops‑секреты хранятся в `secrets/home` и монтируются в
  `/run/user/$UID/secrets/...`.
- Примерный паттерн:
  `systemd.user.services.wg-quick-myuser = { serviceConfig.ExecStart = "wg-quick up /run/user/$UID/secrets/wg.conf"; ... };`
  и управление через `systemctl --user start|stop wg-quick-myuser`.
- Такой подход позволяет изолировать VPN только для сессии пользователя, не меняя глобальный
  routing/DNS для всего хоста и не требуя root‑прав для включения/выключения туннеля.

### Sing-box Reality TUN (хост)

- Секрет: `/run/secrets/vless-reality-singbox-tun.json`, разворачивается sops-nix из
  `secrets/home/vless/reality-singbox-tun.json.sops`.
- Юнит: `systemctl start sing-box-tun` / `systemctl stop sing-box-tun` (ручной запуск). Policy
  routing внутри юнита: `pref 100` — трафик к 204.152.223.171 по main; `pref 200` + `table 200` —
  остальной трафик `default dev sb0`; DNS через `resolvectl dns sb0 1.1.1.1 1.0.0.1` и
  `resolvectl domain sb0 "~."`.
- Требования: установленный `sing-box` в `environment.systemPackages`, секрет должен быть доступен,
  нужны root/CAP_NET_ADMIN (запуск через systemd).
- Проверки: `ip rule`, `ip route show table 200` (должен быть `default dev sb0`),
  `curl --interface sb0 https://ifconfig.me`, `ping -I sb0 8.8.8.8`.
- Xray tun из nixpkgs без jsonv5/tun удалён — используем только sing-box.
- Если нужен автозапуск, добавьте `wantedBy = ["multi-user.target"]` и при необходимости сохраните и
  восстановите прежний default route в `ExecStartPre`/`ExecStopPost` юнита.

### Hyprland и GUI

- Автоперезагрузка Hyprland отключена; перезапускайте хоткеем.
- Конфиги Hypr разбиты на файлы в `files/gui/hypr/*` и линкуются через nix-maid.
- `~/.local/bin/rofi` задаёт дефолтные флаги, автопринятие и поиск тем в XDG путях; отключайте
  автопринятие флагом `-no-auto-select`.
- `pinentry-rofi` по умолчанию запускается с темой `askpass`; переопределяйте флагами через
  переменную `PINENTRY_ROFI_ARGS` при необходимости.
- Индикатор раскладки в Quickshell слушает `keyboard-layout` Hyprland, предпочитает устройство с
  `main: true`, показывает активный submap как пиктограмму акцентом перед клавиатурным глифом и
  раскладкой (например, `★ ⌨ en`), и переключает `hyprctl switchxkblayout current next`.
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

- Пользовательский сервис при входе в систему автоматически делает RNNoise‑источник источником по
  умолчанию (если включено).
- Источник можно выбрать вручную в настройках окружения рабочего стола.

## Defaults, Overrides и mkForce Policy

- Модули задают значения через `mkDefault` (их легко переопределить на хосте простым присваиванием):
  - Примеры: `services.timesyncd.enable`, `zramSwap.enable`, `boot.lanzaboote.enable`,
    `nix.gc.automatic`, `nix.optimise.automatic`, `nix.settings.auto-optimise-store`,
    `boot.kernelPackages` (как `mkDefault`).
- На хостах предпочитайте обычные присваивания:
  - Булевы флаги: `foo.enable = false;`
  - Уникальные опции (например, `boot.kernelPackages`): просто
    `boot.kernelPackages = pkgs.linuxPackages_latest;`
- Используйте `lib.mkForce` только когда нужно зачистить/перебить слияния или спорные уникальные
  значения:
  - Списки: чтобы явно очистить ранее добавленные элементы — `someListOption = lib.mkForce [];`
  - Редкие конфликты уникальных опций от разных модулей.

Примеры

```nix
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

- Proton‑GE часто улучшает производительность/совместимость (установлен). При регрессиях вернитесь
  на Valve Proton.
- MangoHud: `MANGOHUD=1`. Ограничение FPS:
  `MANGOHUD=1 MANGOHUD_CONFIG=fps_limit=237 game-run %command%`. По умолчанию конфиг:
  `etc/xdg/MangoHud/MangoHud.conf`.
- Mesa/AMD:
  - Vulkan ICD по умолчанию RADV (`AMD_VULKAN_ICD=RADV`); переключайте только при необходимости.
  - Для старых GL‑тайтлов помогает `MESA_GLTHREAD=true`.

### Troubleshooting стуттеров

- Убедиться, что VRR активен (OSD монитора/`gamescope --verbose`).
- Проверить, что игра действительно в Gamescope (не встраиваемый лаунчер вне VRR).
- Прогреть шейдер‑кеш (Steam Shader Pre‑Caching включён) — первые минуты возможны микрофризы.
- Если подвисания при автосохранениях/дисковом I/O — проверьте, что игра не установлена на
  перегруженный диск и что нет фонового индексирования.

### Полезные команды

- Показать текущий CPU‑набор процесса: `grep Cpus_allowed_list /proc/<pid>/status`.
- Скопировать пер‑игровой запуск: `game-run %command%` (Steam), `game-run <path>` (вне Steam).

### Продвинуто: Вложенный Wayland (expose-wayland)

- Чтобы запускать нативные Wayland-клиенты внутри Gamescope (или даже вложенный Hyprland),
  используйте `--expose-wayland`.
- Команда: `game-run gamescope --expose-wayland -- %command%`
- Применение: запуск приложений, требующих Wayland-сокет (например, некоторые SDL3 приложения или
  инструменты разработки), или для тестов.
- Примечание: Экспериментально. Возможны проблемы с вводом/фокусом. Не требуется для обычного
  гейминга в Steam/Proton.

## Мониторинг DNS‑резолвера

- Unbound + Prometheus + Grafana для оценивания качества DNS (задержки, DNSSEC‑валидация, кэш‑хиты):
  см. `docs/runbooks/unbound-metrics.ru.md`.

## Grafana: egress и жёсткое ограничение (TODO)

- Возможные источники внешнего трафика и политика его блокировки/разрешения: см.
  `docs/runbooks/grafana-egress-todo.ru.md`.

## Политика «тихой» оценки (Evaluation Noise Policy)

- Не допускаем предупреждений/трейсов во время оценки конфигурации — сборки и переключения должны
  быть «тихими».
- В модулях не используем `warnings = [ … ]`, `builtins.trace`, `lib.warn`.
- Если фича/пакет недоступны — тихо пропускаем или защищаем флагом; поведение документируем в README
  модулей, а не сообщениями во время оценки.
- Ассерты используем только для действительно фатальных конфигураций, которые сломают систему;
  формулируем кратко.

## Hyprland: единый источник и обновления

- Источник истины: `inputs.hyprland` (композитор) закреплён на Hyprland v0.52.1, а `inputs.hy3`
  (плагин) продолжает указывать на `hl0.51.0`; конкретные коммиты фиксирует `flake.lock`.
- Оверлей NixOS переназначает `pkgs.hyprland`, `pkgs.xdg-desktop-portal-hyprland` и
  `pkgs.hyprlandPlugins.hy3` на эти инпуты, так что в модулях достаточно использовать `pkgs.*`.
- Связанные инпуты синхронизируются через `follows` (`hyprland-protocols`,
  `xdg-desktop-portal-hyprland` и др.), дополнительных ручных подключений портала не нужно.
- Не добавляйте `xdg-desktop-portal-hyprland` в `xdg.portal.extraPortals` — сервис уже приезжает
  через `portalPackage`.

Как обновить Hyprland (и hy3):

1. Обновить пины: `nix flake update hyprland hy3` (остальные hyprland‑инпуты подтянутся
   автоматически).
1. Пересобрать систему: `sudo nixos-rebuild switch --flake /etc/nixos#<host>`.

Опционально: при включённом `system.autoUpgrade` добавьте
`--update-input hyprland --update-input hy3` при осознанном переходе на следующий релиз Hyprland.
Обычно обновляем вручную, чтобы контролировать ABI.

## Роли и профили

- Роли: включают наборы через `modules/roles/{workstation,homelab,media}.nix`.
  - `roles.workstation.enable = true;` → рабочая станция (профиль производительности, SSH, Avahi).
  - `roles.homelab.enable = true;` → селф‑хостинг (профиль безопасности, DNS, SSH, MPD).
  - `roles.media.enable = true;` → медиа‑серверы (Jellyfin, MPD, Avahi, SSH).
- Профили: фичи под `modules/system/profiles/`.
  - `profiles.performance.enable` и `profiles.security.enable` переключаются ролями; можно
    переопределять на хосте.
- Профили сервисов: `profiles.services.<name>.enable` (алиас к `servicesProfiles.<name>.enable`).
  - Роли ставят `mkDefault true`; на хосте можно просто выключить `false` (без mkForce).
- Хост‑специфика: храните конкретные настройки под `hosts/<host>/*.nix` (например, имена
  интерфейсов, локальные DNS‑переписи).

## Ядро: PREEMPT_RT

- Переключатель: `profiles.performance.preemptRt.enable = true;`
- Режим: `profiles.performance.preemptRt.mode = "auto" | "in-tree" | "rt";`
  - `auto`: включает in-tree `CONFIG_PREEMPT_RT` на ядрах ≥ 6.12, иначе переключает пакет на
    `linuxPackages_rt`.
  - `in-tree`: принудительно включает `CONFIG_PREEMPT_RT` в текущем пакете ядра (без смены пакета).
  - `rt`: явно переключает пакет ядра на `pkgs.linuxPackages_rt`.

Примечание: внештатные модули (например, `amneziawg`) подтягиваются из выбранного
`boot.kernelPackages`, когда доступны.

## Отладка/профайлинг (опционально)

- Профилирование аллокаций памяти (6.10+):
  `profiles.debug.memAllocProfiling.{enable,compileSupport,enabledByDefault,debugChecks}`.
- perf data‑type профайлинг (6.8+):
  `profiles.debug.perfDataType.{enable,installTools,enableKernelBtf}`.
  - Включение некоторых опций может пересобирать ядро (требуются `CONFIG_*`).

## Охлаждение / Fan Control (тихий профиль)

- Включение датчиков и тихой кривой вентиляторов: `hardware.cooling.*` (модуль:
  `modules/hardware/cooling.nix`).
- Для типичных плат ASUS/Nuvoton модуль грузит `nct6775` и генерирует `/etc/fancontrol` на старте.
- Опционально: добавить вентилятор GPU в тот же профиль
  (`hardware.cooling.gpuFancontrol.enable = true;`).

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
- При `gpuFancontrol.enable = true` вентилятор GPU (amdgpu pwm1) ведётся по температуре GPU
  (желательно «junction» при наличии).
- Если `/etc/fancontrol` уже есть, он разово бэкапится в `/etc/fancontrol.backup` и заменяется
  ссылкой на `/etc/fancontrol.auto`.
- Вентиляторы GPU обычно управляются драйвером; модуль целит только PWM матплаты.
  - Исключение: когда `gpuFancontrol.enable = true`, переводим `pwm1_enable` в ручной режим и
    управление берёт fancontrol.

### Тест возможности полной остановки вентилятора

- Утилита: `fan-stop-capability-test` определяет, какие PWM‑каналы матплаты могут полностью
  остановиться на 0%.
- Безопасность по умолчанию: пропускает CPU/PUMP/AIO; после пробы возвращает исходные значения.
- Примеры:
  - Только список: `sudo fan-stop-capability-test --list`
  - Тест корпусных: `sudo fan-stop-capability-test`
  - Включая CPU/PUMP (на свой риск): `sudo fan-stop-capability-test --include-cpu`
- Опции: `--device <hwmonN|nct6798>`, `--wait <sec>` (по умолчанию 6), `--threshold <rpm>` (по
  умолчанию 50).
- Примечание: для точности остановите `fancontrol` на время теста —
  `sudo systemctl stop fancontrol`.

## GPU CoreCtrl (Undervolt/Power‑Limit)

- Опционально (по умолчанию выключено): `hardware.gpu.corectrl.enable = false;`
- При включении устанавливается CoreCtrl и правило polkit, позволяющее членам выбранной группы
  (`wheel` по умолчанию) использовать helper.
- Опционально: `hardware.gpu.corectrl.ppfeaturemask = "0xffffffff";` — разблокирует расширенные
  OC/UV на некоторых AMD GPU.

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

______________________________________________________________________

# AGENTS: советы и грабли при интеграции мониторинга и post-boot

Post‑Boot Systemd Target

- Не добавляйте `After=graphical.target` в сам `post-boot.target`; `graphical.target` уже хочет
  `post-boot.target`. Добавление `After=graphical.target` на target создаёт цикл упорядочивания.
- Перенося сервисы на post‑boot, избегайте безусловного `After=graphical.target` в хелпере, который
  цепляет юниты к `post-boot.target`. Пусть target будет wanted графическим таргетом, а конкретные
  `After=` добавляйте только по необходимости (никогда не на сам target).

Профиль Wi‑Fi (iwd)

- Базовый сетевой модуль ставит тулзы iwd, но держит `networking.wireless.iwd.enable = false`, чтобы
  проводные хосты не поднимали сервис.
- Если на хосте нужен Wi‑Fi, включите `profiles.network.wifi.enable = true;` (например, в
  `hosts/<имя>/networking.nix`) вместо ручного `lib.mkForce`.

Prometheus PHP‑FPM Exporter

- Доступ к сокету: экспортер читает unix‑сокет PHP‑FPM (например, `/run/phpfpm/app.sock;/status`).
  Убедитесь, что сокет пула PHP‑FPM доступен на чтение группе общего веб‑пула, и экспортер входит в
  неё:
  - Настройте пул PHP‑FPM: `"listen.group" = "nginx";`, `"listen.mode" = "0660"`.
  - Добавьте пользователей `caddy` и `prometheus` в группу `nginx` через
    `users.users.<name>.extraGroups = [ "nginx" ];`.
- Песочница юнита: апстрим‑юнит экспортера может запрещать UNIX‑сокеты через
  `RestrictAddressFamilies`.
  - Разрешите AF_UNIX: `RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];`.
  - Дайте юниту доступ к группе сокета: `SupplementaryGroups = [ "nginx" ];`.
- DynamicUser vs. постоянный пользователь: апстрим может использовать `DynamicUser=true` и
  `Group=php-fpm-exporter`. Чтобы экспортер наследовал статическое членство в группах,
  переопределите с большим приоритетом:
  - `DynamicUser = lib.mkForce false; User = lib.mkForce "prometheus"; Group = lib.mkForce "prometheus";`.
- Экстренная безопасность switch: если при отладке экспортер блокирует активацию, временно отключите
  его, чтобы разблокировать `switch`: `services.prometheus.exporters."php-fpm".enable = false;` и
  включите обратно после фикса прав/порядка.

Типовые ошибки

- Неправильное место для extraGroups: внутри `users = { ... }` задавайте
  `users.caddy.extraGroups = [ "nginx" ];` и `users.prometheus.extraGroups = [ "nginx" ];` (это
  маппится на `users.users.<name>.extraGroups`). Не пишите повторно `users.users.caddy` внутри
  `users = { ... }` — получится `users.users.users.caddy` и сломает оценку. Типовые ошибки с прокси:
  не включайте одновременно разные reverse‑proxy для одного и того же бекенда (например, nginx и
  Caddy на один и тот же сокет/порт) — удобнее придерживаться одного прокси на хост.

Nextcloud на telfir (чистая установка)

- Хост `telfir` использует стандартный модуль `services.nextcloud` без кастомных profiles;
  веб‑фронтенд — Caddy (`services.caddy`) поверх пула PHP‑FPM Nextcloud.
- Nextcloud доступен по `https://telfir`, начальный логин: пользователь `admin`, пароль
  `Admin123!ChangeMe` (см. `hosts/telfir/services.nix:services.nextcloud.config`).
- Директория данных отделена от старых установок (`/zero/sync/nextcloud`), база MariaDB/MySQL
  создаётся локально под пользователем БД `nextcloud` (`database.createLocally = true;`).
- Для сброса пароля админа используйте
  `sudo -u nextcloud /run/current-system/sw/bin/nextcloud-occ user:resetpassword admin`. Текущий
  пароль (`Admin123!ChangeMe` по умолчанию) хранится в SOPS‑секрете
  `secrets/nextcloud-admin-password.sops.yaml`.
  - Пароль подхватывается в систему через юнит `nextcloud-adminpass-from-sops`, который
    разворачивает секрет в `/var/lib/nextcloud/adminpass` (владелец `nextcloud`, права `0400`).
  - Автоматические юниты `nextcloud-setup` и `nextcloud-update-db` отключены; обновление выполняется
    вручную через `sudo -u nextcloud nextcloud-occ upgrade` после смены версии Nextcloud в конфиге.

## Игры: Изоляция CPU и лаунчеры

### Переключатель игрового стека

- Переключение всего игрового стека:

  - `profiles.games.enable = false;` — отключить Steam/Gamescope wrappers/MangoHud на уровне
    системы.
  - По умолчанию `true` для сохранения текущего поведения.

- Изолированные CPU: хост `telfir` резервирует ядра `14,15,30,31` для низколатентного гейминга.
  Системные сервисы остаются на «housekeeping» ядрах.

- Transient scope runner: `game-run` запускает любую команду в пользовательском systemd scope и
  привязывает её к изолированным CPU через `game-affinity-exec`.

- Хелперы Gamescope: `gamescope-pinned`, `gamescope-perf`, `gamescope-quality`, `gamescope-hdr` и
  `gamescope-targetfps` оборачивают `game-run`.

### Steam (опции запуска для каждой игры)

- Базовый: `game-run %command%`
- С Gamescope (fullscreen + VRR): `game-run gamescope -f --adaptive-sync -- %command%`
- Переопределить CPU set для игры: `GAME_PIN_CPUSET=14,15,30,31 game-run %command%`
- Отключить GameMode для игры: `GAME_RUN_USE_GAMEMODE=0 game-run %command%`

### Игры вне Steam

- Запуск напрямую: `game-run /path/to/game`
- С пресетами Gamescope:
  - Performance: `gamescope-perf <game | command-with-args>`
  - Quality: `gamescope-quality <game | command-with-args>`
  - HDR: `gamescope-hdr <game | command-with-args>`
  - Target FPS autoscale: `TARGET_FPS=120 gamescope-targetfps <cmd>`

### Переменные окружения

- `GAME_PIN_CPUSET`: список или диапазоны CPU (по умолчанию `14,15,30,31`). Примеры: `14,30` или
  `14-15,30-31`.
- `GAME_RUN_USE_GAMEMODE`: `1` (по умолчанию) запускать через `gamemoderun`, `0` — отключить.
- `GAMESCOPE_FLAGS`: дополнительные флаги для gamescope в `gamescope-pinned`.
- `GAMESCOPE_RATE`, `GAMESCOPE_OUT_W`, `GAMESCOPE_OUT_H`: переопределить частоту и размер вывода для
  обёрток gamescope.
- `TARGET_FPS`, `NATIVE_BASE_FPS`, `GAMESCOPE_AUTOSCALE`: управление автомасштабированием в
  `gamescope-targetfps`.

### Проверка affinity и scope

- Показать CPU mask текущего шелла: `grep Cpus_allowed_list /proc/$$/status`
- Проверить запуск игры: `game-run bash -lc 'grep Cpus_allowed_list /proc/$$/status; sleep 1'`

## Main User (единый источник правды)

- Настройка основного аккаунта через `users.main.*` в модулях:
  - `users.main.name`: логин (по умолчанию `neg`).
  - `users.main.uid` / `users.main.gid`: ID пользователя/группы (по умолчанию `1000`).
  - `users.main.group`: имя основной группы (по умолчанию равно `users.main.name`).
  - `users.main.description`, `users.main.opensshAuthorizedKeys`, `users.main.hashedPassword`.
- Модули используют это вместо хардкода имён/ID:
  - MPD запускается как `users.main.name` и задаёт `XDG_RUNTIME_DIR` из `users.main.uid`.
  - Bind mounts файловой системы используют home основного пользователя вместо `/home/neg/...`.
  - Extra groups и PAM limits ссылаются на основного пользователя/группу.
- Просмотр transient scope: `systemctl --user list-units 'app-*scope' --no-pager`

Замечания:

- Не оборачивайте весь Steam‑клиент; лучше использовать per‑game Launch Options, чтобы загрузки и
  тулинг оставались на housekeeping CPU.
- Чтобы изменить изолированные ядра по умолчанию, установите `GAME_PIN_CPUSET` в окружении или
  измените изоляцию CPU хоста в `modules/hardware/host/telfir.nix`.

## Рекомендации по гейммингу

- 4K/240 Hz (VRR): используйте Gamescope с fullscreen и VRR для улучшения frame pacing на Wayland.

  - Типовой запуск: `game-run gamescope -f --adaptive-sync -r 240 -- %command%`
  - Если GPU‑limited, апскейл: рендер ниже, вывод native. Пример 1440p→4K:
    `-w 2560 -h 1440 -W 3840 -H 2160 --fsr-sharpness 3`.

- HDR (AMD + Wayland): используйте обёртку `gamescope-hdr` или добавьте `--hdr-enabled` к Gamescope.

  - Требования: HDR включён на мониторе, свежее ядро/Mesa, Gamescope с поддержкой HDR.
  - Некоторым играм нужно включить HDR внутри игры после запуска в HDR‑режиме.

- Латентность и стабильность:

  - Предпочитайте per‑game CPU set: `GAME_PIN_CPUSET=14,15,30,31 game-run %command%`. Если игра
    создаёт много потоков, расширьте (например, `14-15,28-31`).
  - Держите VRR включённым: `--adaptive-sync`. При тиринге или проблемах с синхронизацией попробуйте
    без него и/или ограничьте FPS чуть ниже максимума (например, 237 при 240 Hz) через in‑game
    лимитер или MangoHud.
  - Опционально: проверьте Gamescope `--rt` (realtime scheduling). Если появляется jitter
    аудио/ввода, уберите.

### Субъективные пресеты (мои личные настройки)

Эти пресеты субъективны и экспериментальны — я придумал их сам. Используйте как отправную точку и
настраивайте под своё железо/игру.

- Соревновательный FPS (минимальная латентность, 240 Hz VRR):

  - Steam Launch Options:
    `GAME_PIN_CPUSET=14,15,30,31 MANGOHUD=1 MANGOHUD_CONFIG=fps_limit=237 game-run gamescope -f --adaptive-sync -r 240 -- %command%`
  - Замечания: ограничение ниже максимального refresh (237/240) для стабильных frametimes;
    попробуйте добавить `--rt` к Gamescope, если стабильность ОК; отключите in‑game V‑Sync.

- Кинематографический single‑player (качество, стабильные 120 FPS):

  - Если native 4K устойчив: `game-run gamescope -f --adaptive-sync -r 120 -- %command%`
  - Если GPU‑bound: 1800p→4K апскейл:
    `game-run gamescope -f --adaptive-sync -r 120 -w 3200 -h 1800 -W 3840 -H 2160 --fsr-sharpness 3 -- %command%`
  - Замечания: на панели 240 Hz 120 FPS тоже плавно с VRR и оставляет запас для HDR/RT.

- Тяжёлый DX12/Open‑World (например, RT heavy):

  - Начните консервативно: `TARGET_FPS=110 game-run gamescope -f --adaptive-sync -- %command%`
  - Опциональные RADV‑переключатели (могут меняться с версиями Mesa):
    `RADV_PERFTEST=gpl shadercache` — только если знаете что делаете.

- Стратегия/Сим с множеством воркер‑потоков:

  - Расширьте CPU set для игры: `GAME_PIN_CPUSET=12-15,28-31 game-run %command%`
  - Если стуттеры от фоновых задач — оставьте Gamescope и MangoHud, но уберите `--rt`.

- Эмуляторы / старые GL‑тайтлы:

  - `MESA_GLTHREAD=true game-run %command%`
  - Для строгого frame pacing предпочитайте integer scale в Gamescope или ограничьте FPS до
    делителей native rate.

- HDR‑тайтлы:

  - `game-run gamescope --hdr-enabled -f --adaptive-sync -- %command%`
  - HDR в игре нужно включить; проверьте HDR OSD монитора и логи Gamescope.

Советы по настройке:

- Если увеличивается input lag — уберите `--rt` и слегка понизьте лимит FPS.
- Если GPU на 99% со спайками — снизьте render resolution (`-w/-h`) или примените in‑game апскейлеры
  (FSR/DLSS/XeSS), сохраняя вывод Gamescope на native.
- Если CPU спайки — снизьте фоновую активность или расширьте `GAME_PIN_CPUSET`.

## Лёгкий мониторинг (игровой PC)

- Netdata (локальный, очень лёгкий):

  - Включить на хосте: `monitoring.netdata.enable = true;` (см. `hosts/telfir/services.nix`).
  - Открывает локальный UI на `http://127.0.0.1:19999` с CPU/GPU/sensors/disks/net.
  - Сервис де‑приоритизирован (nice/CPU/IO weights) для минимального влияния.
  - Расширьте через `services.netdata.config`, если нужны дополнительные коллекторы.

- История Sysstat (ультра‑лёгкий):

  - Включить на хосте: `monitoring.sysstat.enable = true;`.
  - Смотреть позже: `sar`, `iostat`, `mpstat`, `pidstat`.

- In‑game overlay (уже включён):

  - Используйте MangoHud: запускайте игры с `MANGOHUD=1`.
  - Переключить логирование: `Shift+F2` (CSV сохраняется в `$XDG_DATA_HOME/MangoHud` по умолчанию).

- VictoriaMetrics (если нужны графики без Grafana):

  - Рекомендуемый стек: `vmagent -> VictoriaMetrics single -> vmui`.
  - Очень низкое RAM/CPU при 10–15 s scrape и 7–14 дней retention.
  - По умолчанию не включён; можно добавить позже как отдельный модуль.
