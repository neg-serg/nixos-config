# Windows-VST на Linux через Wine — сравнение решений (odin)

> Исследование 2026-08-20, собрано субагентами по первоисточникам (GitHub, nixpkgs 26.05, исходники
> Carla). Нерешённые места помечены [unverified] — требуют живой проверки на odin. Контекст: NixOS
> 26.05, wineWow64Packages.stable (wine 11), PipeWire (pw-jack, без jackd), Carla из nixpkgs
> (JACK-only, wine-мост НЕ собран), CLI carlactl для headless-роутинга нативных плагинов.

## Таблица сравнения

| Решение                                                                      | Что делает                                                                                                   | Форматы                                                               | 32/64                                                                                                            | wine                                                                                                                                                                                       | Headless/CLI                                                                                                                                                                                                       | Интеграция с Carla/carlactl                                                                                                           | Nixpkgs                                                                                         | Поддержка                                | Лицензия         | CLI-оценка\* |
| ---------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------- | ---------------------------------------- | ---------------- | ------------ |
| **Carla wine bridge** (`make win32/win64/wine32/wine64` из исходников Carla) | Нативный Carla спавнит один `wine carla-bridge-win64.exe` на плагин; IPC через shared memory                 | VST2 + VST3 (CLAP нет)                                                | 32+64 (win32/win64 мосты)                                                                                        | runtime: wine + автодетект префикса по пути к DLL (каталог с `dosdevices`); wineasio НЕ нужен (JACK даёт `jackbridge-wine*.dll`)                                                           | `carla -n <file.carxp>` (проект обязателен), `--osc-gui=<port>`; carlactl-совместимо (C API: `carla_add_plugin(BINARY_WIN64, PLUGIN_VST2, dllPath,…)`)                                                             | Идеальная: тот же C API, бинарь в `$out/lib/carla`, тип PE-файла детектится libmagic, скан через `carla-discovery-win64.exe` под wine | **Нет** (issue #324094; нужен overlay: mingw-w64 + winegcc, 4 make-таргета) [unverified сборка] | Активна (v2.5.10 2025-07, коммиты 2026)  | GPL-2.0-or-later | 3            |
| **yabridge**                                                                 | Linux .so-чейнлоадеры в `~/.vst{,3}/yabridge`, спавнят wine-процесс `yabridge-host.exe`; UDS + shared memory | VST2 + VST3 + **CLAP**                                                | 64-бит; 32-бит Windows-плагины НЕ работают (bitbridge несовместим с WoW64; nixpkgs собирает `-Dbitbridge=false`) | nixpkgs пинит **wine 9.21** (`wineWow64Packages.yabridge`, WINELOADER захардкожен) — обходит несовместимость 9.22/10.x [unverified: префиксы wineapps на wine 11 откроются этим wine 9.21] | Отдельного standalone нет (нужен хост); с Carla: VST2/VST3 OK (README tested-hosts); через carlactl: `carlactl list`/`run vst3:Name` (симлинки подхватываются корнями `~/.vst3`, `~/.vst`) [unverified end-to-end] | Хорошая: symlinks видны carlactl автоматически; `yabridgectl add/sync/status`                                                         | **Есть: 5.1.1** — и уже установлен на odin (`modules/hardware/audio/dsp.nix`)                   | Активна (5.1.1 2024-11, коммиты 2026-08) | GPL-3.0          | 2–3          |
| **linvst / linvst3**                                                         | Per-plugin .so (linvst.so + lin-vst-server); DAW сканирует .so, плагин живёт в wine                          | VST2; VST3 — отдельный **LinVst3** (beta, 64-бит только, не все фичи) | 64; 32-бит требует win32-wine (Arch wow64 не умеет)                                                              | любой современный 64-бит wine                                                                                                                                                              | Нужен GUI-хост; есть CLI-скрипты линковки                                                                                                                                                                          | В Carla грузится как обычный .so → carlactl может увидеть                                                                             | **Нет**                                                                                         | Активна (2025-12; релиз 4.9 2023)        | GPL-3.0          | 1            |
| **airwave**                                                                  | Wine VST bridge → .so для Linux-хостов; shared memory + XEMBED                                               | VST 2.4 только                                                        | 32+64 (multilib wine)                                                                                            | wine ≥ 1.7.19                                                                                                                                                                              | Нужен хост                                                                                                                                                                                                         | Как обычный .so                                                                                                                       | **Есть: 1.3.3**                                                                                 | Мёртв (2020-07)                          | MIT              | 1            |
| **vst-bridge**                                                               | CLI `vst-bridge-maker` конвертит .dll → .so; .so спавнит wine-хост                                           | VST2 только                                                           | 32+64                                                                                                            | wine + WINEPREFIX                                                                                                                                                                          | CLI-maker есть, хост нужен                                                                                                                                                                                         | Как .so                                                                                                                               | **Нет**                                                                                         | Мёртв (2019)                             | MIT              | 1            |
| **wineasio** (аудио-драйвер, не мост)                                        | ASIO→JACK DLL; регистрация per-prefix (`wineasio-register`)                                                  | —                                                                     | 32+64                                                                                                            | любой; wine 11 может требовать переименования `wineasio64.so`                                                                                                                              | Есть CLI-регистрация; для standalone .exe                                                                                                                                                                          | JACK через pw-jack                                                                                                                    | **Есть: 1.3.0**                                                                                 | Активна (2025-07)                        | LGPL-2.1         | 2            |
| **pwasio / pipeasio** (аудио-драйверы)                                       | ASIO→**PipeWire** (без JACK-слоя)                                                                            | —                                                                     | 64                                                                                                               | PipeWire ≥ 1.6 / 1.4.2                                                                                                                                                                     | CLI-регистрация; для standalone .exe                                                                                                                                                                               | нативный PipeWire                                                                                                                     | **Нет** (надо паковать)                                                                         | Активны (2026-08)                        | GPL-3.0          | 2            |
| **Standalone .exe + ASIO-драйвер**                                           | Windows-VST с собственным standalone-бинарём запускается под wine, открывает JACK/PW-порты                   | зависит от VST                                                        | как у VST                                                                                                        | wineapps-префикс + wineasio/pwasio/pipeasio                                                                                                                                                | Полностью скриптуемо: `wine app.exe` + `jack_connect`/`pw-link`; MIDI — через ALSA-seq/a2jmidid [unverified]                                                                                                       | Независимо от Carla                                                                                                                   | —                                                                                               | —                                        | —                | 2–3          |
| **VSTHost / SAVIHost** (Windows freeware)                                    | Windows-хост под wine: `savihost.exe` рядом с .dll = standalone-приложение                                   | VST2+VST3                                                             | 32+64                                                                                                            | wine + ASIO-драйвер                                                                                                                                                                        | конфиг-файлы, CLI-инвокейшен                                                                                                                                                                                       | через JACK                                                                                                                            | —                                                                                               | freeware (закрытый)                      | —                | 2            |
| **MrsWatson**                                                                | Нативный Linux CLI-VST-хост: `mrswatson --input in.mid --output out.wav --plugin <x.so>`                     | грузит .so (в т.ч. linvst/airwave/vst-bridge обёртки)                 | 64                                                                                                               | не нужен (wine только для обёртки)                                                                                                                                                         | **Чистый CLI end-to-end**                                                                                                                                                                                          | —                                                                                                                                     | форк в nixpkgs? (не проверено)                                                                  | оригинал архивирован, форк жив           | BSD              | 3            |
| **Docker-подход** (bitwigbox и т.п.)                                         | wine+плагины в контейнере                                                                                    | зависит                                                               | 64                                                                                                               | внутри контейнера                                                                                                                                                                          | через хостовый JACK                                                                                                                                                                                                | —                                                                                                                                     | —                                                                                               | активен                                  | —                | 1            |

\*CLI-оценка: 0 = нет, 1 = есть CLI-конвертация, но нужен GUI-хост, 2 = скриптуемый CLI-поток, 3 =
чистый CLI end-to-end.

## Рекомендация для odin (ПРОВЕРЕНО end-to-end 2026-08-20)

**Carla wine bridge — НЕ использовать**: сборка мостов (`make win32/win64`) сломана апстримом в
2.5.10 и master: `OBJS_arch` неполон, make-переменные затирают флаги, winegcc требует multilib,
mingw в nativeBuildInputs отравляет нативную сборку (CC/CXX). Вместо этого — **yabridge** (уже в
nixpkgs, стоит на odin):

1. Префикс VST под wine 9.21 (yabridge host): `wineboot -u` из
   `/nix/store/...-wine-wow64-yabridge-9.21/bin/wineboot`.
1. Windows-VST ставятся в префикс (например ReaPlugs 2.36 x64 — официально wine-tested,
   `/gamez/main/wineapps/reaplugs236_x64-install.exe /S`).
1. `mkdir -p ~/.local/share/yabridge && ln -sf /run/current-system/sw/lib/libyabridge* ~/.local/share/yabridge/`
   → `yabridgectl add "<prefix>/drive_c/Program Files/VSTPlugins/<App>" && yabridgectl sync`.
1. `carlactl list | grep -i rea` → `carlactl run vst2:reaeq-standalone` → headless Carla с плагином.

Фиксы в carlactl (коммит «Route yabridge plugins through carla frontend»):

- yabridge-плагины генерируются через фронтенд-`.carxp` (`carla -n`), а не через in-process C API —
  libyabridge падает в asio epoll_reactor при `add_plugin` (SIGSEGV).
- `NIX_PROFILES` экспортируется в env запуска (nixpkgs-сборка yabridge ищет libs через него).

Проверено: ReaEQ (ReaPlugs) → yabridge 5.1.1 → Carla headless → порты Carla:output_FL/FR в PipeWire.

## Ключевые источники

- Carla wine bridge: https://github.com/falkTX/Carla (INSTALL.md:101–118, CarlaPluginBridge.cpp,
  CarlaBackend.h:1493–1518), nixpkgs issue #324094, https://kx.studio/Applications:Carla. Осторожно:
  открытый регресс `carla --no-gui` #1828 (2.5.7+).
- yabridge: https://github.com/robbert-vdh/yabridge (README, docs/architecture.md,
  tools/yabridgectl/README.md), nixpkgs: pkgs/by-name/ya/yabridge + yabridgectl (wine 9.21,
  -Dbitbridge=false), issues #300755, #399465.
- linvst: https://github.com/osxmidi/LinVst ; LinVst3: https://github.com/osxmidi/LinVst3
- airwave: https://github.com/psycha0s/airwave ; vst-bridge: https://github.com/abique/vst-bridge
- wineasio: https://github.com/wineasio/wineasio ; pwasio: https://github.com/golfiros/pwasio ;
  pipeasio: https://github.com/M0n7y5/pipeasio
- MrsWatson (форк): https://github.com/adamnemecek/MrsWatson ; VSTHost/SAVIHost:
  https://syntheway.com/Hermann_Seib_VSTHost_v1.53_SAVIHost_v1.41.htm
- Винные воркфлоу для VST: https://wiki.nixos.org/wiki/Electric_guitar_interface_setup

\*Открытые вопросы: (1) Carla bridge JACK под pw-jack (LD_LIBRARY_PATH чистится, jackbridge-wine.dll
резолвит libjack) [unverified];

- (2) 32-бит bridge под WoW64 wine 11 [unverified]; (3) yabridge + префикс wine 11 [unverified];
- (4) сборка Carla-мостов в оверлее [unverified].

## Установка VST-пакетов (проверено 2026-08-20, все в префикс `vstplugins`)

- **ReaPlugs 2.36 x64** (Cockos): `wine reaplugs236_x64-install.exe /S` →
  `drive_c/Program Files/VSTPlugins/ReaPlugs/` (10 VST2 dll).
- **The Legend HZ 2.1.0** (Synapse): `wine Legend_HZ_2_1_Setup.exe /S` →
  `Program Files/Steinberg/VSTPlugins/LegendHZ.dll` (VST2) +
  `Program Files/Common Files/VST3/Synapse Audio/LegendHZ.vst3` (VST3) + AAX.
- **kiloHearts Ultimate v2.4.6** (4.3 ГБ): InnoSetup — `/S` НЕ работает (exit 5), нужен
  `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART` → `Program Files/Common Files/VST3/kiloHearts/` (48
  плагинов: Phase Plant, Snap Heap, kHs-модули).
- После установки: `yabridgectl add <каталог с dll/vst3>` + `yabridgectl sync` + `carlactl list`.

### Legend HZ: «запустите от администратора»

- Плагин headless загружается нормально (yabridge init OK), сообщение идёт от лицензионного слоя
  Synapse при открытии UI.
- Причины: (1) тихий `/S` не создаёт `Program Files/Synapse Audio/The Legend HZ/` (создать вручную);
  (2) без регистрации/кейгена плагин остаётся демо-режимом.
- Valhalla-релизы из торрентов (`R2R/`, `R2RINNO.dll` в temp установщика) — это крякнутые
  установщики, их не запускаем; кейгены/патчи тоже.

## «The Wine host process has exited unexpectedly» в GUI-хостах (исправлено)

- **Симптом**: в Carla GUI (и любом десктопном хосте) yabridge-плагины падают с «The Wine host
  process has exited unexpectedly»; в GUI-патчбее у плагина нет MIDI-порта.
- **Причина**: `modules/user/nix-maid/cli/envs.nix` глобально задавал
  `WINEPREFIX=~/.local/share/wineprefixes/default`. yabridge при установленной переменной НЕ
  определяет префикс по пути плагина (README yabridge: WINEPREFIX overrides the Wine prefix for all
  yabridge plugins) — винный хост стартовал в пустом `default`-префиксе и крашился.
- **Фикс**: глобальный `WINEPREFIX` убран из `envs.nix` (коммит 8fa747a0); yabridge сам находит
  префикс по расположению `.dll/.vst3` (`vstplugins`). Проверка: `bash -lc 'echo $WINEPREFIX'` пуст.
  После пересборки десктопной сессии нужен релогин (старые процессы держат старый env).
- **Red/green**: `WINEPREFIX=…/default carla -n LegendHZ.carxp` → «exited unexpectedly» (+45 c);
  `WINEPREFIX=…/vstplugins` → `Finished initializing '…LegendHZ.vst3'`, хост жив.

## Играемая цепочка: carla-jack-single + физическая клавиатура

- Carla GUI (патчбей) НЕ отдаёт MIDI-порты плагинов наружу в этой сборке — для MIDI-входа используем
  `carla-jack-single` (тот же `.carxp`): порт `Carla:LegendHZ:events-in`.
- MIDI: `Midi-Bridge:External MIDI:HDSPe24048964 MIDI 1 (capture)` → `Carla:LegendHZ:events-in`
  (физическая клавиатура, RME MIDI IN; мост строит сам PipeWire, a2jmidid не нужен).
- Audio: `Carla:LegendHZ:output_1/2` → `game-stereo:playback_FL/FR` (game-stereo → RME
  playback_AUX2/3).
- Команды: `pw-link "alsa:seq:default:client_16:capture_0" "Carla:input_0"`;
  `pw-link "Carla:output_0" "game-stereo:playback_FL"` (имена — object.path, без префикса
  «LegendHZ:»).
- **ВНИМАНИЕ (исправлено)**: при запуске Carla ВЕСЬ звук превращался в «кашу» не из-за
  демо-режима Legend HZ, а из-за увода графа PipeWire на 44.1 kHz: Carla (JACK-клиент) переводил
  граф на 44.1k, RME HDSPe (48k) становился resampling-«follower» и сыпал xrun'ы
  (`snd_pcm_avail after recover: Broken pipe`) — от этого «хрипело» всё (mpd/ютуб), а CPU
  pipewire залипал на ~95%.
  **Фикс**: в `files/media/pipewire/pipewire.conf.d/clock-rate.conf` оставлена только
  `default.clock.allowed-rates = [ 48000 ]` (коммит d3758472) — граф залочен на нативной частоте RME.
  Временный аналог до пересборки: `pw-metadata -n settings 0 clock.force-rate 48000`.

## Osmose (Expressive E) + MPE + Legend HZ (research 2026-08-21)

- **Legend HZ**: omni + нативный MPE (мануал Synapse, раздел «5.1 MPE (MIDI Polyphonic Expression)»):
  слушает ВСЕ каналы; переключатель «MPE Controller» — питч-бенд ±48 полутонов, master-канал 1,
  Rise/Fall shaping для CC74/aftertouch. Источник: https://www.synapse-audio.com/legend/TheLegendManualHZ.pdf
- **Osmose**: пресеты External MIDI Mode (Config menu, крутить Value Encoder 4 и нажать): `mpe`
  (по умолчанию: ch1 master + ch2-15 по голосам), `classic keyboard` (всё на ch1 — для legacy-синтов),
  `poly aftertouch`, `multi-channel`. Точная подстройка: Adjust menu → mode tab → «mono ch.» /
  «mpe» (конечный канал) / «multi ch.». Источник: Osmose Manual 1.0, §3 EXTERNAL MIDI MODE.
- **yabridge**: MIDI-паспхру прозрачный, каналы не нормализуются (в yabridge.toml нет MIDI-опций) —
  MPE доходит до Windows-VST без изменений.
- **Вывод**: для Legend HZ менять режим Osmose НЕ нужно — MPE работает напрямую (omni-приём).
  «Странный звук» при первых тестах был из-за демо-режима плагина в общем миксе, а не из-за MPE.
- **MIDI 2.0 (UMP)**: PipeWire 1.6.6 UMP поддерживает (порт «32 bit raw UMP»), но Osmose по USB
  сейчас — класс MIDI 1.0 (bInterfaceProtocol 0), а VST-цепочка (yabridge/Carla) — MIDI 1.0.
  UMP до плагина не доедет без конвертации; вопрос открыт (исследование в работе).
