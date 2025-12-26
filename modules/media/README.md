# Media Module / Модуль медиа

Audio, video, and image processing tools.

Инструменты для работы с аудио, видео и изображениями.

## Structure / Структура

| Path | Purpose / Назначение |
|------|---------|
| `audio/` | PipeWire, audio tools, MPD |
| `images/` | Image viewers/editors / Просмотрщики |
| `scripts/` | Media processing scripts / Скрипты |
| `ai-upscale-packages.nix` | AI video upscaling (RealESRGAN) |
| `multimedia-packages.nix` | FFmpeg, mediainfo, etc. |
| `vapoursynth-packages.nix` | VapourSynth frame server |
| `deepfacelab-docker.nix` | DeepFaceLab container |

## Key Features / Возможности

### AI Upscaling / AI-апскейл

Video upscaling with RealESRGAN:
```bash
ai-upscale-video input.mp4 --anime --scale 4
```

### Audio / Аудио

PipeWire with low-latency configuration for gaming and music.

PipeWire с низкой задержкой для игр и музыки.

### VapourSynth

Frame-by-frame video processing integrated with mpv.

Покадровая обработка видео, интегрированная с mpv.

## Related / См. также

- `modules/user/nix-maid/apps/mpv/` — mpv player
- `modules/servers/mpd/` — Music Player Daemon
