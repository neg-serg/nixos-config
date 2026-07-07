______________________________________________________________________

## name: youtube description: YouTube video search, metadata, and downloads via yt-dlp CLI and WebFetch

# YouTube Operations

Use `yt-dlp` CLI and `WebFetch` instead of MCP YouTube/yt-dlp servers.

## Download Videos

### Best quality

```bash
yt-dlp "URL" --output "~/dw/%(title)s.%(ext)s"
```

### Audio only (mp3)

```bash
yt-dlp -x --audio-format mp3 "URL" --output "~/dw/%(title)s.%(ext)s"
```

### Specific format

```bash
yt-dlp -f "bestvideo[height<=1080]+bestaudio/best[height<=1080]" "URL"
```

### Playlist

```bash
yt-dlp --playlist-start 1 --playlist-end 5 "PLAYLIST_URL"
```

## Search

### Via yt-dlp

```bash
yt-dlp "ytsearch:NIXOS TUTORIAL" --dump-json
yt-dlp "ytsearch5:TOP HITS 2025" --get-title --get-id
```

### Via WebFetch

Use `WebFetch` to search YouTube:

- `https://www.youtube.com/results?search_query=QUERY`

## Metadata

```bash
yt-dlp --print title --print duration --print uploader --print description "URL"
yt-dlp --dump-json "URL" | jq '{title, duration, uploader, view_count, like_count}'
```

## Subtitles

```bash
yt-dlp --write-auto-subs --sub-lang en --skip-download "URL"
yt-dlp --list-subs "URL"
```

## Configuration

Default download directory: `~/dw/` Override with: `-o "PATH/%(title)s.%(ext)s"`
