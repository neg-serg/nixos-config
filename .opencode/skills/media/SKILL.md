______________________________________________________________________

## name: media description: "Audio/video processing, conversion, and analysis via ffmpeg CLI"

# Media Processing

Use `ffmpeg` CLI directly instead of MCP ffmpeg server. Output directory: `~/vid/`.

## Conversion

### Video to another format

```bash
ffmpeg -i input.mp4 -c:v libx264 -c:a aac output.mkv
ffmpeg -i input.mov -c:v libvpx-vp9 -c:a libopus output.webm
```

### Extract audio

```bash
ffmpeg -i input.mp4 -vn -c:a libmp3lame output.mp3
ffmpeg -i input.mp4 -vn -c:a aac output.m4a
```

## Manipulation

### Trim

```bash
ffmpeg -ss 00:01:00 -to 00:02:30 -i input.mp4 -c copy output.mp4
```

### Resize/Scale

```bash
ffmpeg -i input.mp4 -vf "scale=1280:720" output.mp4
ffmpeg -i input.mp4 -vf "scale=-1:720" output.mp4  # maintain aspect ratio
```

### Crop

```bash
ffmpeg -i input.mp4 -vf "crop=w:h:x:y" output.mp4
```

### Concatenate

```bash
# Create file list
echo "file 'part1.mp4'" > files.txt
echo "file 'part2.mp4'" >> files.txt
ffmpeg -f concat -safe 0 -i files.txt -c copy output.mp4
```

## Info & Analysis

```bash
ffmpeg -i input.mp4  # prints codec, resolution, bitrate
ffprobe -v quiet -print_format json -show_format -show_streams input.mp4
```

## Filters

```bash
# Speed up 2x
ffmpeg -i input.mp4 -vf "setpts=0.5*PTS" -af "atempo=2.0" output.mp4

# Add watermark
ffmpeg -i input.mp4 -i logo.png -filter_complex "overlay=10:10" output.mp4

# Extract frames
ffmpeg -i input.mp4 -vf "fps=1" frame_%04d.png  # one frame per second
```

Outputs go to `~/vid/` by default.
