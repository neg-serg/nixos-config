# Voice input for dsh

**Status: nothing to build — this host has voice infrastructure, and it is deliberately switched
off.** Recorded here so the next person does not spend a day writing a `/voice` command that the
configuration would keep disabled anyway.

## What exists

| Piece                                                                                          | Where                                                                                                                            | State                                                                                                                                                                      |
| ---------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `hyprwhspr-rs` — push-to-talk dictation daemon using local `whisper.cpp`                       | `modules/user/session/hyprwhspr.nix`, gated by `features.gui.hyprwhspr.enable` (**default `false`**, `modules/features/gui.nix`) | `services.hyprwhspr-rs.enable` evaluates to **`false`** on odin                                                                                                            |
| Local speech NN servers — Chatterbox TTS `:8000`, Piper TTS `:8001`, `whisper.cpp` STT `:8002` | `hosts/odin/services/policy.nix`, gated by `features.media.audio.speech.enable`                                                  | **`false`**, with the reason in the file: *"Disabled on request (2026-08-28): local speech NN servers (STT/TTS) turned off."* `curl 127.0.0.1:8002` refuses the connection |
| Whisper model + config for the daemon                                                          | `modules/user/session/hyprwhspr.nix` (`ggml-small.bin`, `auto_copy_clipboard: true`)                                             | present, unused while the service is off                                                                                                                                   |

So the capability is a **configuration decision on this host**, not missing dsh code: the pieces are
packaged, wired, and intentionally parked.

## If it is ever enabled

Both flags are off by default; flipping them is the whole change:

```nix
features.gui.hyprwhspr.enable = true;   # dictation daemon (local whisper.cpp, no API keys)
# and/or, for the HTTP STT/TTS endpoints:
features.media.audio.speech.enable = true;
```

No dsh-side integration is required either way, and none should be added:

- `auto_copy_clipboard: true` means the transcript lands on the clipboard, and the TUI's `Ctrl+V`
  pastes clipboard **text** when the clipboard holds no image — so dictation reaches the input line
  as a paste.
- The daemon also feeds the focused window by design; **whether that delivery is typed keystrokes or
  clipboard-only is not verified here** — the service is disabled on this host, so the path could
  not be exercised.

A dsh-side `/voice` would therefore duplicate a working system facility, and would have to keep
working while the flags stay off.

## What is *not* affected

Audio **input into the model** is a separate concern and already works: the TUI attaches images from
the clipboard and the vision bridge describes them for models without vision. Voice is transcription
only — see `docs/howto/dsh-*.md` for the surfaces that do exist.
