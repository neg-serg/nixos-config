# Media Module

Audio, video, and image processing tools.

## Structure

| Path | Purpose |
|------|---------|
| `audio/` | PipeWire, audio tools, MPD |
| `images/` | Image viewers/editors |
| `scripts/` | Media processing scripts |
| `ai-upscale-packages.nix` | AI video upscaling (RealESRGAN) |
| `multimedia-packages.nix` | FFmpeg, mediainfo, etc. |
| `vapoursynth-packages.nix` | VapourSynth frame server |
| `deepfacelab-docker.nix` | DeepFaceLab container |

## Key Features

### AI Upscaling

Video upscaling with RealESRGAN:

```bash
ai-upscale-video input.mp4 --anime --scale 4
```

### Audio

PipeWire with low-latency configuration for gaming and music.

### VapourSynth

Frame-by-frame video processing integrated with mpv.

## Related

- `modules/user/nix-maid/apps/mpv/` — mpv player
- `modules/servers/mpd/` — Music Player Daemon
