# RVC — конверсия голоса с обучением (Retrieval-based Voice Conversion)

Дата установки: 2026-08-29 (проверено, CLI работает). Статус: **venv и ассеты готовы, обучение под
целевой голос — не проведено** (нужен датасет/модель).

## Что это и зачем

- RVC — стандарт индустрии для **конверсии голоса с обучением**: модель тренируется на голосе
  конкретного человека (~10 мин чистого материала) и даёт максимальное сходство с ним. Используется
  для каверов, озвучки, стримов.
- Отличие от Seed-VC: Seed-VC — **zero-shot** (достаточно референс-сэмпла, без обучения); RVC —
  **обучение под голос** (выше точность для конкретного таргета). XTTS — это TTS (текст→речь), не
  конверсия произвольного аудио.
- Русский: работает с русскоязычными данными обучения (сам RVC языконезависим — качество зависит от
  датасета).

## Статус на odin

| Компонент        | Путь                                                    | Статус                      |
| ---------------- | ------------------------------------------------------- | --------------------------- |
| Репозиторий      | `~/src/music-ai/Retrieval-based-Voice-Conversion-WebUI` | клонирован                  |
| venv             | `~/src/music-ai/venv-rvc` (torch 2.13.0+rocm7.1, GPU)   | готов                       |
| hubert           | `assets/hubert/hubert_base.pt` (190 МБ)                 | скачан                      |
| rmvpe            | `assets/rmvpe/rmvpe.pt` (181 МБ)                        | скачан                      |
| CLI              | `infer/cli.py`                                          | грузится на ROCm без ошибок |
| Обученная модель | —                                                       | ❌ нужен целевой голос      |

## Инференс (готовой моделью)

```bash
export LD_LIBRARY_PATH="/nix/store/7vafhlh0lmcvi75jfyy09qwr4m3x1ks3-gcc-15.2.0-lib/lib:/nix/store/483x61iy35irm4wr2b7dwzihljhp6da2-zlib-1.3.2/lib:/nix/store/13id30w3rvgj24nnz34f7qrncz48zd7l-zstd-1.5.7/lib"
cd ~/src/music-ai/Retrieval-based-Voice-Conversion-WebUI
~/src/music-ai/venv-rvc/bin/python infer/cli.py --model weights/MYVOICE.pth --input in.wav --output out.wav --f0-method rmvpe
```

Ключевые опции: `--speaker-id` (мультиголосые модели), `--pitch` (сдвиг в полутонах),
`--index`/`--index-rate` (поиск по эмбеддингам, повышает сходство), `--rms-mix-rate`, `--protect`.

## Обучение под голос

1. **Датасет**: ~10-15 мин чистого голоса целевого человека (без музыки/шума/реверберации), нарезать
   на файлы 3-10 с.
1. **Препроцессинг**: `python train/preprocess.py` (резка, извлечение f0/hubert).
1. **Тренировка**: `python train/train.py` (G/D сети; на RX 9070 XT 16 ГБ: ~10 мин данных × ~50 эпох
   ≈ 30-60 мин).
1. Полученный `.pth` + `.index` → папка `assets/weights/` → инференс.

## Как получить готовую модель

- Свои записи: собрать датасет (см. выше) и обучить.
- Готовая `.pth` с HuggingFace (community-модели):

```bash
# huggingface.co rate-limited — идём через зеркало
curl -L -o model.pth https://hf-mirror.com/<owner>/<repo>/resolve/main/<file>.pth
```

## Ссылки

- Репозиторий: <https://github.com/RVC-Project/Retrieval-based-Voice-Conversion-WebUI>
- Общий отчёт по нейронкам: [neural-stack-report.ru.md](./neural-stack-report.ru.md)
- Zero-shot альтернатива: [seed-vc.ru.md](./seed-vc.ru.md) (документ появится после завершения
  SVC-режима)
