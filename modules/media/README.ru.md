# Модуль медиа

Инструменты для работы с аудио, видео и изображениями.

## Структура

| Путь | Назначение |
|------|------------|
| `audio/` | PipeWire, аудио утилиты, MPD |
| `images/` | Просмотрщики/редакторы изображений |
| `scripts/` | Скрипты обработки медиа |
| `ai-upscale-packages.nix` | AI апскейл видео (RealESRGAN) |
| `multimedia-packages.nix` | FFmpeg, mediainfo, и т.д. |
| `vapoursynth-packages.nix` | Фрейм-сервер VapourSynth |
| `deepfacelab-docker.nix` | Контейнер DeepFaceLab |

## Возможности

### AI-апскейл

Апскейл видео с помощью RealESRGAN:

```bash
ai-upscale-video input.mp4 --anime --scale 4
```

### Аудио

PipeWire с низкой задержкой для игр и музыки.

### VapourSynth

Покадровая обработка видео, интегрированная с mpv.

## См. также

- `modules/user/nix-maid/apps/mpv/` — плеер mpv
- `modules/servers/mpd/` — Music Player Daemon
