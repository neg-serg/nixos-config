# Локальный музыкальный ИИ-стек (odin)

Всё, что относится к нейросетям в музыке/аудио на этой машине: где живёт, как
вызывается, как пересоздать. Дополняет `carlactl.ru.md` (роутинг плагинов через
headless Carla) и `local-llm.md` (речевой стек, LLM).

## Инвентарь venv (все — в ~/src/music-ai/, Python из nix store)

| venv | Python | Назначение | Пересоздать |
|---|---|---|---|
| `venv-rave311` | 3.11 (store `python3-3.11.15`) | acids-rave 2.3.1: RAVE VC/инференс | `uv pip install --python $(ls -d /nix/store/*python3-3.11*/bin/python3.11)/bin/python3.11` не нужно: venv уже создан; пакеты: `uv pip install --python ~/src/music-ai/venv-rave311/bin/python acids-rave` |
| `venv-beat` | 3.11 | madmom (бит), torchcrepe (питч), librosa | numpy==1.23.5 + scipy==1.10.1 (для madmom), затем `--no-build-isolation` madmom; torchcrepe обычным pip |
| `venv-nam` | 3.11 | neural-amp-modeler (NAM inference) | `uv pip install --python .../venv-nam/bin/python neural-amp-modeler` |

Общий паттерн для pip-вещей на NixOS:
`export LD_LIBRARY_PATH=/nix/store/7vafhlh0lmcvi75jfyy09qwr4m3x1ks3-gcc-15.2.0-lib/lib:/nix/store/483x61iy35irm4wr2b7dwzihljhp6da2-zlib-1.3.2/lib:/nix/store/13id30w3rvgj24nnz34f7qrncz48zd7l-zstd-1.5.7/lib`

## RAVE (нейро-автоэнкодер)

- Модели: `/zero/ai/music/rave/*.ts` — guitar (16-латент, 48k), VCTK (голос v1),
  isis + sol_ordinario (вокальные v2, официальные IRCAM), crozzoli (18-латент).
- **RaveLive** (живой процессор в SuperCollider): класс в
  `~/.local/share/SuperCollider/Extensions/rave-live/RaveLive.sc`.
  Цепочка `SoundIn -> NN(\rave,\encode) -> манипуляции -> NN(\rave,\decode) -> out`,
  контролы amount/morph/freeze/gain, OSC /rave/ctl (Tidal). Латентность ~85 мс.
  Документация: `/zero/ai/music/rave-live/README.md` + `tidal-rave.md`.
- **Voice conversion**: `rave-vc IN.wav OUT.wav [--src isis] [--tgt sol_ordinario]`
  (обёртка над `/zero/ai/music/rave-live/vc.py`, ресемпл на 48k автоматически).
  Демо: `/zero/ai/music/rave-live/demo/`.
  Важно: латент-размерности моделей различаются (isis=8, sol=4) — конверсия работает
  через AdaIN-нормализацию декодера, качество оцени на слух.

## NAM (Neural Amp Modeler) — нейро-усилитель

- Плагин: `~/.lv2/neural_amp_modeler.lv2` (v0.2.3, Linux x64, GPL-3.0,
  mikeoliphant/neural-amp-modeler-lv2). В Carla доступен как LV2; headless — через
  `carlactl list --format lv2` (см. carlactl.ru.md).
- Путь плагинов: `LV2_PATH` задан в envs.nix
  (`~/.lv2:/run/current-system/sw/lib/lv2`).
- Модели (.nam каптуры): `/zero/ai/music/nam-models/` (пример — Ceriatone King Kong).
  Большой каталог: tonehunt.org. Инференс вне Carla: `venv-nam` + python
  (init_from_nam; tkinter-заглушка при импорте; старые .nam v0.5.0 — только в плагине).
- Цепочка: гитара → Carla → NAM (усилитель) → RAVE (морфы) → запись/Tidal.

## Биты и питч (для Tidal-синхрона)

- `audio-beats FILE` — BPM + времена битов (madmom, оффлайн; веса CC BY-NC-SA —
  личное использование ок). Вывод: `bpm 137.06` + секунды.
- `pitch-f0 FILE [--notes] [--hop MS] [--model tiny|full]` — f0-кривая
  (torchcrepe, CPU ~14x realtime на tiny; --notes добавляет MIDI-ноты).
  Выход: `time f0 [midi]` на кадр.

## Прочее

- OCR: `got-ocr` (GOT-OCR-2.0, китайский/сложные документы) и `pic-ocr`
  (tesseract/qwen3-vl, русский).
- Все обёртки в `packages/local-bin/bin/`; после изменений — `nh os switch`.
