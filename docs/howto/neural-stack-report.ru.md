# Отчёт: тестирование нейросетевых инструментов на odin

Дата проверки: **2026-08-28**. Хост: odin (NixOS, AMD RX 9070 XT, Ryzen 9 9950X3D, 60 ГБ RAM). Цель
— проверить, что все установленные нейро-инструменты реально работают после сборки, починить
сломанное, задокументировать статус. Все модели живут в `/zero/ai/**`.

## Сводная таблица

| Инструмент     | Назначение                                      | Статус      | Проверено                     |
| -------------- | ----------------------------------------------- | ----------- | ----------------------------- |
| `whisperx`     | STT + диаризация (faster-whisper, CPU)          | ⚠️ STT ✓, align ✗ | 2026-08-29: распознавание ru ✓ («Привет! Это тест синтеза речи…»); **alignment/диаризация зависают** (регрессия — 19.08 работало; нужна отладка, вероятно версии torch/lightning) |
| `mt3`          | аудио → MIDI (MR-MT3, PyTorch)                  | ✅ работает | 171 нота; **GPU (ROCm): 11.2s vs 30.3s CPU** (40s трек, результат идентичен, 2026-08-29) |
| `midi-transcribe` | hFT-Transformer / RobustAMT (пианино)      | ✅ работает | CPU: `midi-transcribe`; **GPU (ROCm): `midi-transcribe-gpu`** — hFT 40s за ~11s вместо 20+ мин CPU (2026-08-29, venv-denoise + torch 2.13 rocm7.1) |
| ~~`amt-generate`~~ | ~~генерация MIDI (Anticipatory Music Transformer)~~ | ❌ удалён | 2026-08-28, решение пользователя |
| `audio-analysis` | Essentia key/beat + CLAP-теги + мастеринг | ✅ работает | 2026-08-29: Zinovia → **B minor (conf 0.85), ~110 BPM**; CLAP: ambient 0.169. ROCm-torch в venv-analysis |
| `pitch-f0`        | f0-трекинг (torchcrepe) | ✅ работает | 2026-08-29: 2164 фрейма, f0 49-50 Гц, CPU >10x realtime |
| `got-ocr`         | OCR (GOT-OCR-2.0) | ✅ работает | 2026-08-29: венв починен (не было python), OCR картинки ~20s CPU |
| `denoise`        | шумоподавление    | ✅ работает | внутри transcribe-high (noisereduce), 2026-08-28 |
| `song2midi`      | Omnizart (аккорды/вокал/бас/барабаны) | ✅ работает | 2026-08-29: аккорды 15s за ~30s (TF/CPU) |
| `stems`          | BS-RoFormer выделение вокала | ✅ работает | 2026-08-29: **GPU авто + fp16: 16s vs 64s** (×4) на 40s |
| `audio-beats`    | BPM/биты (madmom) | ✅ работает | 2026-08-29: 82 BPM на Zinovia-сегменте |
| `midi2tidal`     | MIDI → Tidal-код  | ✅ работает | 2026-08-29: паттерн из zinovia_best (полифония 6) |
| `transcribe-high --tidal` | пайплайн + Tidal-код | ✅ работает | 2026-08-29: темп 109.1 BPM, паттерн сгенерирован |
| `groovae`        | groove-humanize (magenta GrooVAE) | ✅ работает | **GPU (ROCm)** 2026-08-29: драм-луп humanize (venv-groovae + torch rocm) |
| `xtts-clone`    | клон голоса XTTS-v2 (zero-shot)     | ✅ работает | **GPU (ROCm)** 2026-08-29: синтез на GPU (venv-xtts + torch 2.8 rocm6.4; требует свободную VRAM — ollama её занимает) |
| `rave`/`rave-vc` | нейро-VAE encode/decode + конверсия голоса | ✅ работает | **GPU (ROCm)** 2026-08-29: 10s аудио за ~10-13s (venv-rave311 + torch rocm; обёртка переведена с сломанного venv-rave) |
| `demucs`        | разделение источников (htdemucs_ft) | ✅ работает | torch rocm установлен (venv-demucs, минус 2 ГБ nvidia); **GPU fp32 ≈ CPU** (9.7 vs 10.9s), fp16 ломается внутри — дефолт остаётся CPU |
| `transcribe-high` | конвейер: деноиз→Demucs→basic-pitch→слияние | ✅ работает | проверен 2026-08-28 (см. детали); для чистых записей лучше `--no-denoise --no-stems` |
| `basic-pitch`  | полифоническая транскрипция → MIDI              | ✅ работает | melody10s → MIDI (ONNX)       |
| `rembg`        | удаление фона (u2net / bria-rmbg / birefnet)    | ✅ работает | u2net + bria                  |
| `triposr`      | картинка → 3D-меш                               | ✅ работает | mesh.obj 7.2 МБ               |
| `audio-analysis master` | мастеринг по референсу (matchering) | ✅ работает | 2026-08-29: Zinovia + DOOM-реф → **-13.3 → -9.8 dB** |
| `vsmlrt-models` | ONNX-модели vs-mlrt (mpv-апскейл) | ⏳ качается | 812 МБ с GitHub (прокси добавлен в обёртку) → /zero/ai/imgproc/vsmlrt-v15.16 |

## Детали по инструментам

### whisperx — STT + диаризация

- Обёртка: `packages/local-bin/bin/whisperx` (venv `~/src/music-ai/venv-whisperx`).
- Команда: `whisperx audio.wav --model small --language ru --diarize --output_dir out/`.
- Результат: `/tmp/whisperx-out/test-ru.{txt,srt,vtt,json,tsv}` — распознавание + разметка спикеров.
- Сосуществует с `whisper.cpp` (:8002) из speech-стека — это другой бэкенд.

### mt3 — транскрипция аудио в MIDI

- Обёртка: `packages/local-bin/bin/mt3` (venv `~/src/music-ai/venv-mt3`, инференс
  `~/src/music-ai/mt3-infer`).
- Команда: `mt3 file.wav [out.mid]`; чекпоинт MR-MT3 в `/zero/ai/music/mt3/mr_mt3`.
- Результат: `/tmp/mt3-out.mid` — 171 нота.

### ~~amt-generate~~ — удалён (2026-08-28)

Пользователь признал генерацию «хернёй»; удалены: обёртки `~/src/music-ai/bin/amt-*`,
venv `venv-amt` (включая torch 2.13.0+rocm7.1), исходники `anticipation/`, модели
`music-small-100k`/`music-small-ar-100k` (980 МБ), артефакты и колёса
(`/zero/ai/music/renders/amt-20260828/`, `/zero/ai/music/tmp-dl/`), symlink в
`~/.local/bin`.

### basic-pitch — полифоническая транскрипция

- Обёртка: `packages/local-bin/bin/basic-pitch` (venv `venv-bp`) — **новая**, форсирует
  `--model-serialization onnx`: встроенный TF saved_model несовместим с TF 2.21.
- Команда: `basic-pitch OUT_DIR audio.wav --save-midi`.
- Результат: `/tmp/bp-test/melody10s_basic_pitch.mid`.

### rembg — удаление фона

- Обёртка: `packages/local-bin/bin/rembg` (venv `venv-rembg`). Дефолт — `-m u2net`, если
  пользователь не передал свой `-m` (bria-rmbg-2.0 качался с заблокированного GitHub).
- Модели в `/zero/ai/imgproc/models/`: `u2net/u2net.onnx`, `bria-rmbg/bria-rmbg.onnx` (1.02 ГБ,
  скачан через socks-прокси с релиза danielgatis/rembg), `birefnet-general/birefnet-general.onnx`.
- Команда: `rembg i in.png out.png`; `rembg i -m birefnet-general in.png out.png`.
- Результат: `/tmp/rembg-out4.png`, `/tmp/rembg-bria.png`.

### triposr — картинка → 3D

- Обёртка: `packages/local-bin/bin/triposr` (venv `venv-triposr`, torch CPU +
  torchmcubes/xatlas/moderngl).
- Модель VAST-AI/TripoSR (~700 МБ) в `/zero/ai/3d` (HF_HOME).
- Команда: `triposr img.png --output-dir out`.
- Результат: `/tmp/triposr-out3/0/mesh.obj` (7.2 МБ) — раньше виснул на скачивании bria-модели,
  после установки bria в `/zero/ai/imgproc` работает.

## Починенные проблемы

1. **Сломанные venv из-за python 3.14** (системный python теперь 3.14.7, пакеты в venv лежат в
   `lib/python3.12` или 3.13 → ModuleNotFoundError). Починено перелинковкой `bin/python3` на
   store-path 3.12.13:
   `ln -sfn /nix/store/71d4s2c3dfqk4afkjp8w8g4l3f1glcsy-python3-3.12.13/bin/python3.12 $venv/bin/python3`
   \+ `ln -sfn python3 $venv/bin/python`. Затронуты: whisperx, amt, mt3, bp, rembg, triposr, denoise,
   analysis.
1. **numba 0.67 сломан на py3.12** (`coverage.types`) → `pip install 'numba<0.62'` (0.61.2 +
   llvmlite 0.44 + numpy 2.2.6).
1. **rembg тянет bria-rmbg-2.0.onnx с GitHub** (заблокирован) → модель скачана через socks5h-прокси
   (`127.0.0.1:10808`) в `/zero/ai/imgproc/models/bria-rmbg/`; обёртка по умолчанию использует
   u2net.
1. **basic-pitch: TF saved_model битый на TF 2.21** → обёртка форсирует ONNX-сериализацию.
1. **venv-demucs** (bin→3.14, пакеты в 3.13): пересоздан на python3.13, CPU-торч ставился первым
   (`pip install torch==2.8.0 --index-url https://download.pytorch.org/whl/cpu`), иначе pip тащит
   CUDA-торч + 2 ГБ nvidia-колёс.
1. **colibri serve: «Address already in use»** на 8000/8001/8002 → ручной порт **8003**; сервис
   выключен по умолчанию (включается вручную).

## Инфраструктура

- **venv**:
  `~/src/music-ai/venv-{amt,analysis,bp,demucs,denoise,groovae,magenta,midi2tidal,mt3,nam,omnizart,rave,rave311,rembg,tags,triposr,whisperx,xtts}`.
- **Обёртки**: `packages/local-bin/bin/` (Nix-управляемые; тест — прямой путь из репозитория, в
  `~/.local/bin` попадают после `nh os switch`). `amt-generate` — symlink на `~/src/music-ai/bin/`.
- **Модели (`/zero/ai`)**: `3d` (TripoSR), `imgproc` (rembg/u2net/bria/birefnet, RealESRGAN,
  vs-mlrt), `music` (mt3/mr_mt3, rave, nam-models, separation, instruments), `speech`
  (piper/whisper.cpp/cosyvoice-engines, voices), `whisperx` (hub), `ocr` (got-ocr2, paddleocr),
  `image` (flux/sdxl/taesd), `llama` (qwen3-vl, glm gguf), `ollama` (23 модели), `glm52_i4`
  (colibri, 144 шардов/384 ГБ), `embeddings`, `t5-summarization`, `video` (comfyui).
- **Порты**: 8000 = omnirouter (LLM), 8001 = piper TTS, 8002 = whisper STT, 8003 = colibri (ручной
  запуск), 11434 = ollama.

## Коммиты (2026-08-28)

- `3b00ea9e` — `[docs]` нейро-инструменты в howto local-music-ai + обёртки `basic-pitch` (новая) и
  `rembg` (u2net-дефолт).
- Ранее в сессии: `5389989a` (venv-demucs doc), `0c11f102` (colibri serve 8003), `60d29a89` (colibri
  manual serve doc, serve off).

## Не проверено / отложено

- `audio-analysis`, `denoise`, `groovae` venv — там тоже был битый bin/python (3.14); symlink-фикс
  применён, но повторный прогон не делался.
- `colibri` — сервис выключен по умолчанию (решение пользователя); ручной рецепт: см.
  `docs/howto/local-llm.md`.
- Обёртки вступят в силу после `nh os switch /etc/nixos#odin --option substitute false`.
