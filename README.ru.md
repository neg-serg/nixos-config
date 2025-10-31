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
