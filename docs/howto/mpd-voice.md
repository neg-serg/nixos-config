# MPD voice client (`mpd-voice`)

Voice control for the local Music Player Daemon: one microphone utterance becomes an MPD command,
and the confirmation is spoken back.

```
microphone -> capture + VAD -> WAV -> STT backend -> phrase
           -> rule parser -> MPD (protocol client) -> reply -> TTS backend
```

| Piece           | Where                                                                                             |
| --------------- | ------------------------------------------------------------------------------------------------- |
| Program         | `packages/mpd-voice` (Python, standard library only)                                              |
| Flag            | `features.media.audio.mpdVoice.enable` (default `true`)                                           |
| Module          | `modules/media/audio/mpd-voice.nix` (install + `/etc/xdg` config)                                 |
| Speech backends | `features.media.audio.speech` (whisper.cpp STT `:8002`, piper `:8001`) — separate flag, still off |
| Unit tests      | `packages/mpd-voice/tests/` (`python -m unittest discover -s tests -t .`)                         |

## Why the client is not a daemon

The host's speech stack is parked on purpose (`dsh-voice.md` explains the decision), so the voice
client must stay usable without it:

- Installing the package starts nothing and opens no microphone. The CLI is inert until it is run or
  bound to a key.
- Speech recognition is pluggable: an OpenAI-compatible HTTP server (`http`), `whisper-cli` directly
  (`cli`), or any command that prints a transcript (`cmd`).
- `mpd-voice say` and `mpd-voice status` work with no audio at all, and `mpd-voice doctor` reports
  which backend actually resolved on this host.

## Usage

```console
$ mpd-voice doctor                    # MPD + capture + STT + TTS: what works here
$ mpd-voice once                      # push-to-talk: one utterance, then exit
$ mpd-voice listen                    # keep listening (every utterance acts)
$ mpd-voice listen --wake-word music  # only act on utterances with the keyword
$ mpd-voice say "next track"          # typed command, same pipeline, no microphone
$ mpd-voice say "similar tracks"      # queue neighbours of the current track
$ mpd-voice say "play dark music"     # queue tracks by mood (MTG tagger output)
$ mpd-voice say --speak "volume 30"   # also speak the reply
$ mpd-voice status --json             # scriptable now-playing
$ mpd-voice phrases                   # every supported phrase, both languages
$ mpd-voice parse "volume 40"         # show how a phrase is parsed
```

Russian and English phrases are both understood; the reply language follows the language of the
utterance (`--lang` forces one). `mpd-voice phrases` prints the corpus — English phrases are also
the best starting point for a new binding.

Exit codes: `0` executed, `1` backend/MPD failure, `3` nothing was executed (phrase not understood,
or no wake word in the one-shot mode).

## Push-to-talk binding

`once` is the push-to-talk path. It is bound in the Hyprland config (`files/gui/hypr/hyprland.lua`)
right next to the media keys — `SHIFT+W` is play/pause, `SHIFT+Q` talks to the player:

```lua
hl.bind(M4 .. "+" .. SH .. "+q", hl.dsp.exec_cmd("mpd-voice once"), { locked = true })
```

`SUPER+Q/W/E` keep their run-or-raise targets (nwim / browser / Telegram), so the voice bind uses
the free shifted slot beside them. `locked = true` makes it fire while a locked window (a password
prompt) has focus, and Hyprland resolves binds against the US layout
(`resolve_binds_by_sym = false`), so the key works under the Russian layout as well.

Alternative trigger: bind the dictation path instead (`mpd-voice say "$(wl-paste)"`) if the
transcript already lands on the clipboard, e.g. through hyprwhspr.

## Configuration

`/etc/xdg/mpd-voice/config.toml` is written by the module; `~/.config/mpd-voice/config.toml`
overrides it key by key; command line flags override both.

```toml
[mpd-voice]
language = "ru"           # reply + default recognition language (ru|en)
wake_word = ""            # keyword for `listen` (empty = act on everything)
stt = "auto"              # auto|http|cli|cmd|none
stt_url = "http://127.0.0.1:8002"   # OpenAI-compatible STT base URL
tts = "auto"              # auto|http|cmd|none
tts_url = "http://127.0.0.1:8001"   # OpenAI-compatible TTS base URL
similar_cmd = "music-similar --json -k 10"  # neighbour provider for `similar tracks`
music_dir = "~/music"     # must match MPD's music_directory (helper wants real paths)
# mood queue: JSONL produced by `music-mtg-tags --dir ~/music --out FILE --json`
tags_file = "~/.cache/music-mtg/tags.jsonl"
tags_min_score = 0.10     # mood label score floor (measured scores: 0.1-0.4)
tags_min_seconds = 45.0   # drop records whose audio_seconds is below this (0 = off)
tags_exclude = "samples/*"  # comma-separated globs relative to music_dir ("" = none)
tags_limit = 25           # max tracks queued per mood request (0 = no cap)
```

`similar tracks` (also `more like this`, `find similar`, `queue similar`) appends neighbour tracks
of the currently playing song. The neighbours come from the local `music-similar` helper, and its
embedding index is built by the `music-index` / `music-embed` tooling described in
`local-music-ai.md`. `music_dir` must match MPD's `music_directory`: MPD reports file paths relative
to it, while the helper takes absolute paths.

`play dark music` (also `play something sad`, `play relaxing music`, `play happy music`,
`play epic music`, `play heavy music`, `play space music`, `play meditative music`,
`play romantic music`, and the same phrases with `add`) appends shuffled tracks whose Jamendo mood
label clears `tags_min_score` in the JSONL named by `tags_file`, capped at `tags_limit`. The labels
come from the trained `mtg_jamendo_moodtheme` head (see `local-music-ai.md`), not from audio file
tags, so the JSONL must be generated first:

```console
$ music-mtg-tags --dir ~/music --out ~/.cache/music-mtg/tags.jsonl --json
```

Two filters keep one-shot samples out of the queue. `tags_exclude` is a comma-separated list of
`fnmatch` globs matched against the track path relative to `music_dir`; the default `samples/*`
covers the measured offender (two-second VCSL piano notes under `~/music/samples`), and an empty
string disables the filter. `tags_min_seconds` (default 45.0) drops records whose `audio_seconds` —
the decoded length the tagger analysed — is below the floor; `0` disables it. 45 s is a sane floor
for "music, not a sample": real tracks run for minutes, while instrument samples are seconds long.

Tag files written before the tagger recorded `audio_seconds` have no such field. Those records
cannot be judged, so they are kept — an old cache keeps working instead of silently emptying every
mood queue. To get `audio_seconds` into the whole cache, re-tag from scratch: a plain re-run resumes
by mtime+size+settings and leaves the old lines untouched, so remove the JSONL first, then let the
tagger skip samples at the source:

```console
$ rm ~/.cache/music-mtg/tags.jsonl
$ music-mtg-tags --dir ~/music --out ~/.cache/music-mtg/tags.jsonl --exclude 'samples/*' --min-seconds 20
```

A missing file, a missing `music_dir`, an empty match or a file whose every line is broken become a
spoken error, never a traceback.

Command line overrides worth knowing: `--stt cli --stt-model FILE` (direct whisper.cpp),
`--stt cmd --stt-cmd 'record-and-transcribe {wav}'`, `--tts cmd --tts-cmd 'espeak-ng -v ru {text}'`,
`--tts none`, `--capture arecord --device hw:1,0`, `--no-confirm`, `--wake-word WORD`.

Environment: `MPD_HOST`, `MPD_PORT`, `MPD_PASSWORD` (mpc-compatible), `MPD_VOICE_LANG`,
`MPD_VOICE_STT`, `MPD_VOICE_TTS`, `MPD_VOICE_TAGS_FILE`, `MPD_VOICE_TAGS_EXCLUDE` (an empty value
means no exclude patterns).

Backends and their `auto` order:

| Stage   | `http`                                  | `cli`                                   | `cmd`                               |
| ------- | --------------------------------------- | --------------------------------------- | ----------------------------------- |
| STT     | `/v1/audio/transcriptions` on `stt_url` | `whisper-cli`                           | command printing a transcript       |
| TTS     | `/v1/audio/speech` on `tts_url`         | —                                       | command speaking `{text}`           |
| Capture | —                                       | `pw-record`, `arecord`, `ffmpeg`, `sox` | command writing s16le PCM to stdout |

`auto` for STT probes the HTTP server first, then `whisper-cli`; for TTS it probes HTTP, then
`spd-say` / `espeak-ng` / `espeak` / `say`. If nothing resolves, `say`/`status` keep working and
`doctor` says what is missing.

## Behaviour notes

- `play album|artist|genre|folder|playlist ...` replaces the queue and starts playback; `add ...`
  appends. `similar tracks` appends neighbours of the current track without disturbing playback, and
  an unrecognised phrase never touches MPD at all.
- `similar tracks` runs `similar_cmd` with the absolute path of the current song and maps the JSON
  paths back to MPD URIs relative to `music_dir`. No current song, a missing file, an empty result
  list, a failed helper or unparsable JSON become a spoken error, never a traceback.
- Mood phrases (`play dark music`, `play something sad`, ...) stream `tags_file` once, keep tracks
  whose matching mood label scores at or above `tags_min_score`, drop records whose `audio_seconds`
  is below `tags_min_seconds` (records without the field are kept — older tag files predate it) and
  paths matching a `tags_exclude` glob, shuffle what is left, cap the result at `tags_limit` and
  append the MPD URIs to the queue. Broken JSONL lines are skipped (all-broken is reported with the
  line count) and paths outside `music_dir` are ignored.
- Search is MPD's case-insensitive `search`: an exact tag match first (`Album`, `Artist`, `Genre`,
  `Title`, `file`), then `search any`.
- Volume is clamped to 0-100; `mute` remembers the level and `unmute` restores it. Outputs without a
  mixer report `-1` and `setvol` is a no-op — the client says the volume is unsupported instead of
  pretending.
- An MPD `ACK` becomes a spoken error (`No such playlist`, `No song loaded`), never a traceback.

## Tests

```console
$ cd packages/mpd-voice
$ python3 -m unittest discover -s tests -t .            # unit + fake-daemon tests
$ MPD_VOICE_TEST_MPD=1 python3 -m unittest discover -s tests -t .   # + private mpd(1)
$ MPD_VOICE_E2E=1 python3 -m unittest discover -s tests -t .        # + espeak-ng -> whisper.cpp
```

- Unit tests drive the parser, the MPD protocol client (against an in-process fake daemon speaking
  real protocol bytes), the VAD/recorder, the STT/TTS backends (against a local HTTP stub and fake
  command-line tools) and the mood queue (against a fixture `music-mtg-tags` JSONL).
- `MPD_VOICE_TEST_MPD=1` starts a private `mpd` on a spare port with a generated FLAC library (needs
  `mpd` and `ffmpeg`), so the full phrase → queue → playback path runs against a real daemon without
  touching the user's session or queue.
- `MPD_VOICE_E2E=1` synthesises speech with `espeak-ng`, transcribes it with `whisper-cli` and
  asserts the recognised phrase turns into the expected intent and MPD action — a real voice round
  trip with no human speaker.
