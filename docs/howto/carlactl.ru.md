# carlactl — консольный роутер внешних VST через headless Carla

`carlactl` запускает установленные VST-плагины (Vital, Dexed, Stochas и т.п.) в
Carla в полностью неинтерактивном режиме и маршрутизирует их аудио-выходы в
PipeWire-граф. Там, где нужен выбор (какой плагин, какой проект), используется
fzf; всё остальное работает без GUI и без ввода.

## Почему так устроено

- Сборка Carla на этом хосте — **только JACK** (нет нативного PipeWire), а `jackd`
  отсутствует: JACK эмулирует PipeWire. Поэтому всё запускается под `pw-jack` с
  `LD_LIBRARY_PATH=/run/current-system/sw/lib` (тот же паттерн, что у `tidalctl`).
- Headless-режим Carla (`carla -n`) **требует файл проекта .carxp**. Проект
  генерируется программно через C-API Carla (`libcarla_standalone2.so`:
  `engine_init` → `add_plugin` → `save_project`) — GUI не нужен вообще.
- Плагины в NixOS изолированы в /nix/store; в `/run/current-system/sw/lib/{vst3,vst}`
  они попадают автоматически через `environment.systemPackages` (см. `*_PATH` в
  `modules/system/environment.nix`).

## Команды

| Команда | Что делает |
| --- | --- |
| `carlactl list [--format vst3,vst2]` | список установленных плагинов (быстро, по именам файлов) |
| `carlactl run vst3:Vital` | сгенерировать .carxp и запустить Carla headless |
| `carlactl run` (без аргумента) | выбор плагина через fzf |
| `carlactl stop` | остановить Carla |
| `carlactl status` | pid + порты Carla в графе PipeWire |
| `carlactl route [mix|an|aes|spdif|phones|none]` | куда слать аудио-выход (RME AUX-пары, как в pwroute) |
| `carlactl projects [имя]` | сохранённые .carxp, запуск через fzf |

Состояние: `~/.local/state/carlactl/` (pid, лог, проекты, кэш списка плагинов).

## Примеры

```console
$ carlactl list --format vst3
vst3	Dexed		/run/current-system/sw/lib/vst3/Dexed.vst3
vst3	Stochas		/run/current-system/sw/lib/vst3/Stochas.vst3
vst3	Vital		/run/current-system/sw/lib/vst3/Vital.vst3

$ carlactl run vst3:Vital
started Carla headless (pid 12345) with vst3:Vital
project: ~/.local/state/carlactl/projects/Vital.carxp

$ carlactl status
Carla: running (pid 12345)
Carla:output_FL ...
Carla:output_FR ...

$ carlactl route aes      # аудио на RME AUX2/AUX3
$ carlactl stop
```

## Тонкие моменты

- **Формат плагина**: Carla грузит Linux VST2/VST3 (native-бридж). CLAP discovery
  не поддерживается, LV2 обрабатывается по-другому (bundle = много плагинов) —
  для LV2 используйте ZestBay/`zest`.
- **MIDI**: Vital — синтезатор, ему нужен MIDI-вход. В текущей версии маршрутизация
  MIDI-источника (SuperDirt/Tidal, железная клавиатура, Stochas) ещё не
  реализована в `carlactl` — порты Carla можно соединить вручную через `pw-link`
  (например `SuperCollider:midi-out → Carla:midi-in`).
- **Скорость list**: mega-bundle lsp-plugins.vst3 содержит ~100 плагинов, поэтому
  имена берутся из имён файлов, а не из discovery (быстро), плюс кэш по mtime
  каталогов. После пересборки системы кэш инвалидируется сам.
- **fzf и неинтерактив**: там, где нужен выбор, без аргумента и без TTY команда
  завершается с понятной ошибкой — в скриптах всегда можно передать `vst3:Имя`
  или путь.

## Где что лежит

- `packages/carlactl/carlactl.py` — сам CLI
- `packages/carlactl/default.nix` — обёртка (пути Carla + pw-jack)
- `packages/overlay.nix` — регистрация пакета (`pkgs.neg.carlactl`)
- `modules/media/audio/creation-packages.nix` — установка в систему
- `modules/system/environment.nix` — `CLAP_PATH` добавлен в `pluginPaths`

## Vital standalone (звук сейчас, без Carla)

Пока headless Carla не отдаёт MIDI-вход, звук проще получать standalone-приложением
из того же пакета `pkgs.vital` (бинарь `Vital`): встроенная клавиатура, аудио
авто-подключается (`Vital → game-stereo → RME`).

- Юнит: `systemctl --user start vital-standalone` (pw-jack + `LIBGL_ALWAYS_SOFTWARE=1`,
  чтобы не было чёрного окна на Wayland/XWayland).
- Описание юнита: `modules/media/audio/creation-packages.nix`
  → `systemd.user.services.vital-standalone`.

## MIDI (Tidal → Vital) — фундамент заложен

Управлять Vital из Tidal пока нельзя: на хосте не загружен ALSA-секвенсор (snd-seq).
В конфиг добавлено:

- `hosts/odin/hardware.nix` → `boot.kernelModules`: `snd-seq`, `snd-seq-midi`
  (вступает в силу после пересборки + перезагрузки).
- После ребута: `aconnect -l` должен показать MIDI-порты; дальше — MIDI-выход
  SuperDirt (`superdirt_startup.scd`, живёт в ~/notes) → MIDI-вход Vital,
  и паттерны Tidal через SuperDirt MIDI.
