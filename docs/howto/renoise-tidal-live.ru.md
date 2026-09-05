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
    just renoise-osc    # OSC-CLI для Renoise (renoise-osc help / --help)
    just renoise-record # захват аудио Renoise в wav (см. «Запись»)

Raw-SuperCollider (scnvim, без Tidal): хоткей M4+Shift+t → sc-live (live.scd,
s.boot в сессии). Renoise/плагины: synth LegendHZ, synth Surge_XT, …; класс
Renoise всегда на workspace 12 «daw». Запуск самого Renoise (run-or-raise):
M4+Shift+a — фокусирует открытое окно Renoise или запускает его.

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
    renoise-osc transport start|stop|continue|panic|toggle
    renoise-osc bpm 128           # темп (20–999); lpb 1–255; tpl 1–16
    renoise-osc loop pattern on   # зациклить паттерн / loop block on|off
    renoise-osc loop sequence 1 8 # диапазон цикла по секвенции
    renoise-osc track 1 mute|unmute|solo
    renoise-osc track 1 volume 0.8 | volume-db -6 | pan 0.5
    renoise-osc instr 1 volume-db -3 | transpose 12 | macro 3 0.5
    renoise-osc device 1 1 bypass on     # трек, устройство, on|off
    renoise-osc record [--secs 30] [--target renoise] [--out FILE]
    renoise-osc eval '…lua…'      # произвольный Lua через /renoise/evaluate
    renoise-osc reverb [--track master|N] [--wet X]
    renoise-osc load 'Legend HZ'  # новый инструмент + VST (сам запустит Renoise, если надо)
    renoise-osc help <cmd>        # развёрнутая помощь по команде
    renoise-osc --dry <cmd> …     # показать OSC-сообщение, не отправляя

Команды оборачивают документированные адреса из GlobalOscActions.lua
(поставка Renoise): transport/loop, song/bpm|lpb|tpl, track/instrument/device
параметры. Ответов сервер не шлёт (fire-and-forget); ошибки eval видны в
консоли скриптинга Renoise.

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

## Запись и рендер в Renoise

Renoise — трекер без аудио-дорожек, поэтому «запись» бывает двух видов.

**1) Офлайн-рендер песни (лучшее качество, финальный микс).**
Меню File → Export Audio…: выбираешь формат (WAV/FLAC/OGG), sample rate
(48 kHz), битность, громкость/нормализацию; рендерится вся песня (или
выбранный диапазон/треки). Это делается в GUI — в OSC/Lua API экспорта нет.

**2) Живой захват сессии (что реально звучит, включая live-входы).**
Renoise-аудио авто-линкуется в sink game-stereo (сервис renoise-link), поэтому:

    just renoise-record                  # в ~/src/art/music/renoise/recordings/
    renoise-osc record --secs 30         # те же 30 секунд
    renoise-osc record --target renoise  # только Renoise, без остального микса
    renoise-osc record --out ~/x.wav     # свой путь (pw-record под капотом)

Стоп: Ctrl+C либо ограничь --secs. SuperDirt-сессия пишется так же:
just tidal-record (в ~/src/art/music/tidal/recordings/); любой поток —
sc-record <сек> или pw-record --target playback.game-stereo.

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
