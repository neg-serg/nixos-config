# mpd-voice

Voice control for MPD. One microphone utterance goes through local speech recognition, becomes an
intent ("next track", "volume 40", "play album …") and is executed against the Music Player Daemon;
the confirmation is spoken back through the same local speech stack.

```
microphone -> [capture + VAD] -> WAV -> [STT backend] -> phrase
           -> [rule parser] -> [MPD client] -> reply -> [TTS backend]
```

Rust, no crates: the MPD protocol client, capture argv, voice activity detection, the HTTP speech
clients and the rule parser are all std. Speech recognition and synthesis stay outside the client,
because that is a deployment decision.

## Commands

```console
$ mpd-voice once                 # push-to-talk: one utterance, then exit
$ mpd-voice listen --wake-word music
$ mpd-voice say "next track"     # typed, same pipeline, no audio
$ mpd-voice say "similar tracks" # queue neighbours of the current track
$ mpd-voice say "play dark music"  # queue tracks by mood (MTG tagger output)
$ mpd-voice say --dry-run "volume 40"   # parse only
$ mpd-voice status --json
$ mpd-voice phrases              # every supported phrase, both languages
$ mpd-voice doctor               # MPD, capture, STT, TTS: what works here
```

What is Rust (`nix build .#mpd-voice` runs the unit tests):

| Module          | Ports                          | Notes                                                                                                                                                  |
| --------------- | ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `src/mpd.rs`    | `mpd_voice/mpd.py`             | full wire protocol client: quoting, `Key: value` parsing, `ACK` decoding, command lists, playback/volume/seek/modes/queue/search/playlists. No crates. |
| `src/toml.rs`   | `tomllib` usage in `config.py` | flat `[section]` + scalar subset; an unreadable document is skipped exactly like a `TOMLDecodeError`.                                                  |
| `src/config.rs` | `mpd_voice/config.py`          | defaults, TOML overlay with Python coercion rules, XDG path chain, `MPD_*` / `MPD_VOICE_*` environment overrides.                                      |
| `src/song.rs`   | `session.py` helpers           | `song_title`, `song_artist`, `song_duration`, `duration_to_clock`, `describe`.                                                                         |
| `src/main.rs`   | `status`, `doctor`, `ping`     | `status` output is byte-identical to the Python CLI, JSON included; `doctor` prints the MPD and config sections, the backend probes are still Python.  |

The Python tree is now only the reference implementation used for the parity harness — every module
has a Rust counterpart.

The speech gate is diffed against the Python one over synthetic signals (silence, one and two
bursts, a blip shorter than the minimum, a loud/quiet switch, a noise ramp, a partial trailing frame
— 24 signal/silence combinations), comparing the event sequence, the utterance length and a checksum
of the kept bytes: all identical.

The controller has its own in-crate fake MPD (`src/testing.rs`, the shape of the Python suite's
`fake_mpd.py`): 24 tests drive phrases through `Controller` and assert on the daemon state — queue,
transport, volume/mute, modes, seek, playlists, mood selection from a tag file, the `similar` and
`describe` helpers, offline handling and "an unknown phrase leaves MPD alone".

`once`/`listen --once` with `--input-wav` and an HTTP STT stub end in the same MPD state and print
the same reply as the Python client, including the wake-word gate (a transcript without the keyword
exits 3 and changes nothing).

The whole CLI is diffed against the Python one over `tests/fake_mpd.py`: 50 phrases through `say`
(replies and exit codes), plus `status`, `status --json`, `parse`, `phrases` and `doctor` —
identical.

The HTTP backends are diffed against Python through the repository's own stub servers
(`tests/stub_servers.py`): the transcript, the multipart fields and the uploaded file bytes match,
and the error strings for an HTTP 500/503 are identical.

Parity for the parser is checked the same way as for `status`: every phrase from the Python test
suite and every documented example, plus generated utterances (2200+ cases), give identical JSON and
exit codes; the engine itself was diffed against Python's `re` over 8946 pattern/text pairs.

## Checks

```console
$ nix build .#mpd-voice-rs            # builds the binary and runs `cargo test`
$ nix run .#mpd-voice-rs -- status    # same env vars as mpd-voice: MPD_HOST, MPD_PORT
```

Parity harness used for `status`: start `tests/fake_mpd.py` from the Python package, point both
clients at its port, compare stdout/stderr/exit code for `status` and `status --json`.
