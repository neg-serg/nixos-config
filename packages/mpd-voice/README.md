# mpd-voice

Voice control for MPD.  One microphone utterance goes through local speech
recognition, becomes an intent ("next track", "volume 40", "play album ...")
and is executed against the Music Player Daemon; the confirmation is spoken
back through the same local speech stack.

```
microphone -> [capture + VAD] -> WAV -> [STT backend] -> phrase
           -> [rule parser] -> [MPD client] -> reply -> [TTS backend]
```

Standard library only: the MPD protocol client, capture, voice activity
detection and the HTTP speech clients are hand-rolled, so the package pulls no
Python dependencies.  Speech recognition itself is delegated to a local
backend, because that is a deployment decision, not a program decision.

## Commands

```console
$ mpd-voice once                 # push-to-talk: one utterance, then exit
$ mpd-voice listen --wake-word music
$ mpd-voice say "next track"     # typed, same pipeline, no audio
$ mpd-voice say --dry-run "volume 40"   # parse only
$ mpd-voice status --json
$ mpd-voice phrases              # every supported phrase, both languages
$ mpd-voice doctor               # MPD, capture, STT, TTS: what works here
```

`say` is the scripting interface: it never touches the microphone and never
speaks unless `--speak` is given.  `listen --once` (aliased as `once`) is the
push-to-talk path suitable for a compositor key binding.  `listen` without
`--once` loops; combined with `--wake-word` it ignores anything that does not
contain the keyword.

Both Russian and English phrases are understood; the reply language follows
the language of the utterance (override with `--lang`).

## Backends

| Stage   | `http`                                        | `cli`                     | `cmd`                          |
| ------- | --------------------------------------------- | ------------------------- | ------------------------------ |
| STT     | OpenAI-compatible `/v1/audio/transcriptions`  | `whisper-cli` (whisper.cpp) | any command printing a transcript |
| TTS     | OpenAI-compatible `/v1/audio/speech`          | —                         | any command speaking `{text}`  |

Capture backends: `pw-record`, `arecord`, `ffmpeg` (pulse), `sox`, or a custom
command template.

`auto` (the default) probes in this order:

1. STT: HTTP endpoint at `stt_url` -> `whisper-cli` with `stt_model` -> error.
2. TTS: HTTP endpoint at `tts_url` -> `spd-say` / `espeak-ng` / `espeak` /
   `say` -> silent.
3. Capture: first of `pw-record`, `arecord`, `ffmpeg`, `sox` found in `PATH`.

`mpd-voice doctor` reports exactly which of them resolved on the current host,
which is the fastest way to diagnose "it hears nothing".

## Configuration

`/etc/xdg/mpd-voice/config.toml` (installer) and
`~/.config/mpd-voice/config.toml` (user, wins):

```toml
[mpd-voice]
mpd_host = "127.0.0.1"
mpd_port = 6600
language = "ru"
wake_word = "music"
volume_step = 5
silence_seconds = 0.8
max_seconds = 8.0

stt = "cli"
stt_bin = "whisper-cli"
stt_model = "/path/to/ggml-large-v3-turbo.bin"
# or: stt = "http"; stt_url = "http://127.0.0.1:8002"
# or: stt = "cmd";  stt_cmd = "hyprwhspr --once {wav}"

tts = "cmd"
tts_cmd = "espeak-ng -s 165 -v ru {text}"
# or: tts = "http"; tts_url = "http://127.0.0.1:8001"; tts_voice = "ru_RU-irina-medium"
```

Environment: `MPD_HOST`, `MPD_PORT`, `MPD_PASSWORD` (mpc-compatible) plus
`MPD_VOICE_LANG`, `MPD_VOICE_STT`, `MPD_VOICE_TTS`.  Command line flags win
over both files and environment.

## Behaviour notes

- `play ...` (album, artist, genre, folder, playlist) replaces the queue and
  starts playing; `add ...` appends instead.  Nothing else edits the queue.
- Searches use MPD's case-insensitive `search`; an exact tag match is tried
  first and falls back to `search any` (file paths included).
- Volume is clamped to 0-100; `mute` remembers the previous level and
  `unmute` restores it.
- Unknown phrases are never guessed: the client says it did not understand
  and leaves the player alone.
- Invalid MPD commands surface as an `ACK` from the server, which is turned
  into a spoken error instead of a crash.

## Tests

```console
$ python3 -m unittest discover -s tests -t . -v              # unit + fake-MPD tests
$ MPD_VOICE_TEST_MPD=1 python3 -m unittest discover -s tests -t . -v
$ MPD_VOICE_E2E=1 python3 -m unittest discover -s tests -t . -v
```

- Unit tests cover the parser, the MPD protocol client against an in-process
  fake daemon, the VAD/recorder and the STT/TTS backends against local stubs.
- `MPD_VOICE_TEST_MPD=1` additionally starts a private `mpd` on a spare port
  with a generated library (needs `mpd` and `ffmpeg`).
- `MPD_VOICE_E2E=1` synthesises speech with `espeak-ng`, transcribes it with
  `whisper-cli` and feeds the transcript to the parser — a real
  voice-to-command round trip without a human speaker.
