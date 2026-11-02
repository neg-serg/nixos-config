# mpd-voice-rs

Rust port of `mpd-voice`, stage 1. The Python package in `../mpd-voice/` is still the installed one;
this crate grows until it reaches parity, then replaces it and the Python tree goes away.

What is already Rust (`nix build .#mpd-voice-rs` runs the unit tests):

| Module          | Ports                          | Notes                                                                                                                                                  |
| --------------- | ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `src/mpd.rs`    | `mpd_voice/mpd.py`             | full wire protocol client: quoting, `Key: value` parsing, `ACK` decoding, command lists, playback/volume/seek/modes/queue/search/playlists. No crates. |
| `src/toml.rs`   | `tomllib` usage in `config.py` | flat `[section]` + scalar subset; an unreadable document is skipped exactly like a `TOMLDecodeError`.                                                  |
| `src/config.rs` | `mpd_voice/config.py`          | defaults, TOML overlay with Python coercion rules, XDG path chain, `MPD_*` / `MPD_VOICE_*` environment overrides.                                      |
| `src/song.rs`   | `session.py` helpers           | `song_title`, `song_artist`, `song_duration`, `duration_to_clock`, `describe`.                                                                         |
| `src/main.rs`   | `status`, `doctor`, `ping`     | `status` output is byte-identical to the Python CLI, JSON included; `doctor` prints the MPD and config sections, the backend probes are still Python.  |

Still Python: capture, VAD, STT/TTS backends and the session/controller logic.

Parity for the parser is checked the same way as for `status`: every phrase from the Python test
suite and every documented example, plus generated utterances (2200+ cases), give identical JSON
and exit codes; the engine itself was diffed against Python's `re` over 8946 pattern/text pairs.

## Checks

```console
$ nix build .#mpd-voice-rs            # builds the binary and runs `cargo test`
$ nix run .#mpd-voice-rs -- status    # same env vars as mpd-voice: MPD_HOST, MPD_PORT
```

Parity harness used for `status`: start `tests/fake_mpd.py` from the Python package, point both
clients at its port, compare stdout/stderr/exit code for `status` and `status --json`.
