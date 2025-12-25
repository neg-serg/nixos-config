## Нейронные модели Essentia (Русский)

В конфигурации уже есть комплект `essentia-extractor` (Essentia 2.1 beta2) и Python-обёртка CLAP.
Ниже перечислены доступные модели и профили.

### Высокоуровневые классификаторы `streaming_extractor_music`

В профиле Music Extractor присутствуют нейросети, которые возвращают семантические теги:

- `genre_dortmund`, `genre_rosamerica`, `genre_tzanetakis` – жанровые классификаторы, обученные на
  разных корпусах.
- `danceability` – пригодность трека для танцев.
- `gender`, `age_rating` – оценка пола и возраста голоса.
- `voice_instrumental`, `voice_presence` – насколько слышен вокал и преобладает ли инструментальное
  звучание.
- Модули настроения: `moods_mirex`, `moods_acoustic`, `moods_aggressive`, `moods_electronic`,
  `moods_happy`, `moods_party`, `moods_relaxed`, `moods_sad`, `moods_instrumental`, `moods_voice`,
  `moods_timbre`.
- `tonal_atonal` – тональность против атональности.

> **Важно:** В открытой сборке Essentia эти классификаторы появляются только при наличии весов. Если
> в JSON нет блока `highlevel`, нужно установить пакет с моделями (Essentia распространяет его
> отдельно).

### Другие профили извлечения признаков

Помимо универсального профиля доступны специализированные инструменты:

- `streaming_extractor_lowlevel` – спектральные и временные дескрипторы.
- `streaming_extractor_tonal` – ключ, лад, расстройка, HPCP.
- `streaming_extractor_rhythm` и `streaming_extractor_beats` – темп, доли, пики атак.
- `streaming_extractor_summary` – агрегированные признаки для каталогов.
- `streaming_extractor_freesound_general` и `streaming_extractor_freesound_music` – классификаторы
  для Freesound (сцены, качество, инструменты).

Каждый профиль – это YAML-граф, лежащий в примерах Essentia. Его можно запускать напрямую или
использовать в качестве шаблона для собственных сетапов.

### Интеграция CLAP

- Пакет `pkgs.neg.laion_clap` включает веса LAION-CLAP, токенизатор Roberta и все зависимости
  PyTorch.
- Пакет `pkgs.neg.music_clap` предоставляет CLI `music-clap` (батчевое извлечение эмбеддингов,
  сравнение с текстовыми запросами, сохранение `.npy`).
- Чекпоинты складываются в кэш (`$LAION_CLAP_CACHE` / `$XDG_CACHE_HOME` / `~/.cache/laion_clap`),
  так что Nix store остаётся неизменным.

### Полезные команды

- `streaming_extractor_music файл.wav результат.json`
- `music-highlevel каталог/ --taxonomies moods_mirex genre_dortmund`
- `music-clap музыка/ --text "атмосферный дум-метал" --dump ~/.cache/music-clap`

#### Примеры использования

- **Темп / BPM**

  ```sh
  streaming_extractor_rhythm трек.wav ритм.json
  jq '.rhythm.bpm' ритм.json
  ```

  Профиль ритма также выдаёт `rhythm.onset_times` и `rhythm.beats_position`, что удобно для трека
  синхронизаторов и даунбитов.

- **Тональные признаки (тональность, лад, строй)**

  ```sh
  streaming_extractor_tonal трек.wav тональность.json
  jq -r '.tonal.key_key, .tonal.key_scale, .tonal.tuning_frequency' тональность.json
  ```

- **Пакетное извлечение семантических тегов**

  ```sh
  music-highlevel ~/music --taxonomies moods_mirex genre_dortmund --output результаты
  ```

  На выходе будет по одному JSON на файл; см.
  `jq '.highlevel.moods_mirex.value' результаты/трек.json`, чтобы посмотреть вероятности тегов.

- **Сравнение CLAP с несколькими подсказками**

  ```sh
  music-clap ~/music --text "blackened doom metal" --text "cinematic ambient" --limit 10
  ```

  CLI выводит косинусные сходства и помогает найти треки, лучше всего подходящие под каждое
  описание.

- **Сохранить эмбеддинги в кэше**

  ```sh
  music-clap ~/music --text "blackened doom metal" --dump ~/.cache/music-clap
  ```

  Веса модели кладутся в `$LAION_CLAP_CACHE` (по умолчанию `~/.cache/laion_clap`); флаг `--dump`
  сохраняет вектор для каждого трека на диск.

- **Низкоуровневые спектральные признаки**

  ```sh
  streaming_extractor_lowlevel трек.wav низкоуровневые.json
  jq '.lowlevel.spectral_centroid.mean' низкоуровневые.json
  jq '.lowlevel.mfcc.mean' низкоуровневые.json
  ```

  Средние и стандартные отклонения удобно использовать в своих ML-пайплайнах.

- **Итоговая сводка по альбому**

  ```sh
  find ~/music/альбом -type f -name '*.flac' > файлы.txt
  streaming_extractor_summary --list файлы.txt сводка.json
  jq '.summary.statistics.mean.bpm' сводка.json
  ```

  Профиль summary агрегирует дескрипторы по нескольким трекам — быстрое средство для каталогизации.

- **Выгрузка CLAP-эмбеддингов для скриптов**

  ```sh
  music-clap ~/music --dump ~/.cache/music-clap
  python - <<'PY'
  import numpy as np
  ref = np.load('$HOME/.cache/music-clap/song.npy')
  other = np.load('$HOME/.cache/music-clap/other.npy')
  print(ref @ other / (np.linalg.norm(ref) * np.linalg.norm(other)))
  PY
  ```

  Дамп повторяет структуру папки; `.npy` можно подхватывать из Python и считать косинусные
  похожести.

- **Указать PyTorch использовать больше ядер**

  ```sh
  music-clap ~/music --text "blackened doom metal" --torch-threads 12
  ```

  При необходимости настройте `--torch-inter-op-threads`, если стандартного пула межоператорных
  потоков не хватает.
