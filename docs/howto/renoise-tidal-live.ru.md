# Renoise + TidalCycles: ежедневный live-coding воркфлоу на odin

Краткая шпаргалка для музыкальных сессий. Оба стека живут в системе декларативно
(NixOS + nix-maid); ниже — команды, порты и грабли, которые встречаются на практике.

## Команды быстрого старта (Justfile)

    just renoise        # Renoise под pw-jack (JACK-драйвер в общий PipeWire-граф)
    just tidal-start    # SuperDirt-движок (sclang + scsynth), ждёт готовности ≤120 с
    just tidal-status   # процессы, OSC-порты, аудио-линки
    just tidal-demo     # движок + демо-сцена в nvim
    just tidal-record   # запись SuperDirt → ~/src/art/music/tidal/recordings/
    just tidal-edit     # workspace + ghci-терминал (tidal-ghci) в nvim
    just tidal-monitor  # pw-top
    just renoise-osc    # OSC-CLI для Renoise (см. ниже)

Raw-SuperCollider (scnvim, без Tidal): хоткей M4+Shift+t → sc-live (live.scd,
s.boot в сессии). Renoise/плагины: synth LegendHZ, synth Surge_XT, …; класс
Renoise всегда на workspace 12 «daw».

## Два движка не запускаются одновременно

Оба используют порты SuperCollider 57110 (scsynth) / 57120 (OSC SuperDirt):

- Tidal-сессия: tidalctl start поднимает headless sclang+SuperDirt
  (лог: ~/.local/state/tidalctl/engine.log, маркер готовности
  SUPERDIRT READY). Дальше — nvim с .tidal-файлом: <leader>tl (launch
  Tidal/ghci), <M-CR>/<leader>ts (отправить паттерн), <leader>tb (весь
  буфер), <leader>th (hush), <leader>tq (quit).
- Raw-SC сессия: НЕ запускать tidalctl; sc-live сам делает s.boot внутри
  scnvim-сессии (sclang-pwj).

## Renoise OSC (удалённое управление из шелла)

Renoise OSC-сервер: UDP 127.0.0.1:9002 (протокол Udp). Порты 9000/UDP заняты
glm-osc (Genelec SAM) — не возвращай Renoise на 9000.

    renoise-osc-config            # прописать в Config.xml: enabled/Udp/9002 (Renoise закрыт!)
    renoise-osc status            # Renoise запущен? порт слушается?
    renoise-osc transport start   # /renoise/transport/start
    renoise-osc transport stop    # stop
    renoise-osc transport toggle  # start/stop через Lua
    renoise-osc transport panic   # panic
    renoise-osc eval '…lua…'      # произвольный Lua через /renoise/evaluate
    renoise-osc reverb [--track master|N] [--wet X]
    renoise-osc load 'Legend HZ'  # новый инструмент + VST (сам запустит Renoise, если надо)

Документированные адреса (без ответов — fire-and-forget): transport
start/stop/continue/panic, loop/*, song/bpm|lpb|tpl, instrument/track/device
параметры (см. GlobalOscActions.lua в поставке Renoise). Ошибки eval видны в
консоли скриптинга Renoise, не в CLI.

## Пути и воркспейсы (канон)

- Workspace сессий: ~/src/art/music/tidal/ (tt.tidal, demo.tidal, recordings/,
  samples/). Реальные проекты — файлы рядом в этом каталоге.
- Journey-файлы — симлинки в приватный ~/notes/music/tidal/
  (BootTidal.hs, demo.tidal, scratch.tidal) и ~/notes/music/supercollider/
  (superdirt_startup.scd и пр.) — их правит сам пользователь, git-версионирует
  notes-репозиторий.
- Boot: ~/.config/tidal/BootTidal.hs → notes. Старт SuperDirt:
  ~/.config/SuperCollider/superdirt_startup.scd → notes (там же грузятся
  семплы/buffers: piano162, acoustic, vsco_strings, winds, IR).
- ghci/tidal: обёртка tidal-ghci из systemPackages (GHC + TidalCycles),
  tidal-edit открывает её в nvim-терминале.

## Аудио/миди

- Sink game-stereo (48 kHz / quantum 256) → RME AES (AUX0/1). Линки
  портов Renoise/SuperCollider в game-stereo держат user-сервисы
  renoise-link.service и supercollider-link.service.
- MIDI: физическая клавиатура RME → Renoise; SC→Renoise — midi-bridge;
  virtual-midi out0-3 — стабильные слоты для синтов; glm-midi — Genelec GLM
  по rtpMIDI (см. windows-vm-dockur.ru.md).

## Запись

- SuperDirt: just tidal-record (pw-record, target = SuperCollider:out*).
- Любой поток sink: sc-record <сек> / pw-record --target playback.game-stereo.

## Грабли (проверено)

1. tidalctl/tidal-ghci не найдены → прошлые system-генерации GC'нуты:
   сделай nh os switch /etc/nixos#odin --option substitute false (пакеты в
   systemPackages). Не храни store-пути в ручных скриптах — только через PATH.
2. Renoise OSC молчит → Config.xml сбит (например, после правки в GUI):
   закрой Renoise и прогони renoise-osc-config; проверь renoise-osc status.
3. Нет звука из Renoise → сервис renoise-link должен быть active
   (systemctl --user status renoise-link); порты JACK называются
   renoise:output_01_left/right.
4. Engine.log: no synth or sample named 'p162' → в паттерне используется
   несуществующее имя инструмента/сэмпла (буфер piano162 грузится, но SynthDef
   называется иначе) — правь паттерн или superdirt_startup.scd, затем
   tidalctl restart.
5. Демо-песни из /nix/store открывать нельзя (backup-ошибки при автосейве) —
   работай с проектами в ~/src/art/music/tidal или ~/notes/music/renoise.
6. NeuralTranscribe тул (Tools → Neural MIDI Transcription): грузится после
   фикса strict-global guard (rawget); ошибки импорта MIDI — в
   ~/.local/share/renoise-neural/.
7. tidalctl start падает с qt.qpa/xcb (SuperDirtMixer хочет Qt, а запуск без
   дисплея): новая версия сама ставит QT_QPA_PLATFORM=offscreen при отсутствии
   WAYLAND_DISPLAY/DISPLAY — просто обнови систему.

## Ссылки

- Windows-VST через yabridge: wine-vst-bridge.ru.md
- Локальные нейронки/распознавание: local-music-ai.ru.md, neural-stack-report.ru.md
- OSC API Renoise: https://tutorials.renoise.com/wiki/Open_Sound_Control
