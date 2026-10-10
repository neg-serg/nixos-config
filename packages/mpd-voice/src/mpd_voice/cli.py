"""Command line interface: `mpd-voice <command> [options]`.

Subcommands:
  once      listen for one utterance and act on it (the push-to-talk path)
  listen    keep listening; with --wake-word only act after the keyword
  say       run typed commands through the same pipeline (no audio)
  status    print what MPD is doing right now
  parse     show how a phrase is parsed (debugging, docs)
  phrases   list the supported phrases in both languages
  doctor    check MPD, capture, STT and TTS backends
"""

from __future__ import annotations

import argparse
import json
import sys
import tempfile
from dataclasses import asdict
from pathlib import Path

from . import __version__
from . import audio
from . import config as config_module
from . import intents
from . import stt as stt_module
from . import tts as tts_module
from .mpd import MPDClient, MPDConnectionError, MPDError
from .session import Controller, describe

EXIT_OK = 0
EXIT_ERROR = 1
EXIT_UNKNOWN = 3


def _add_common_options(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--config", metavar="FILE", help="config.toml to read")
    parser.add_argument("--host", dest="mpd_host", help="MPD host")
    parser.add_argument("--port", dest="mpd_port", type=int, help="MPD port")
    parser.add_argument("--password", dest="mpd_password", help="MPD password")
    parser.add_argument(
        "--lang",
        dest="language",
        choices=("ru", "en"),
        help="reply language",
    )
    parser.add_argument("--verbose", "-v", action="store_true", default=None)
    parser.add_argument("--json", action="store_true", help="machine output")


def _add_voice_options(parser: argparse.ArgumentParser) -> None:
    parser.add_argument(
        "--wake-word",
        dest="wake_word",
        metavar="WORD",
        help="only react to phrases containing this word",
    )
    parser.add_argument(
        "--no-confirm",
        dest="confirm",
        action="store_false",
        default=None,
        help="do not speak confirmations",
    )
    parser.add_argument(
        "--stt",
        choices=("auto", "http", "cli", "cmd", "none"),
        help="speech recognition backend",
    )
    parser.add_argument("--stt-url", dest="stt_url", metavar="URL")
    parser.add_argument("--stt-bin", dest="stt_bin", metavar="PATH")
    parser.add_argument("--stt-model", dest="stt_model", metavar="FILE")
    parser.add_argument("--stt-cmd", dest="stt_cmd", metavar="CMD")
    parser.add_argument(
        "--tts", choices=("auto", "http", "cmd", "none"), help="speech backend"
    )
    parser.add_argument("--tts-url", dest="tts_url", metavar="URL")
    parser.add_argument("--tts-voice", dest="tts_voice", metavar="NAME")
    parser.add_argument("--tts-cmd", dest="tts_cmd", metavar="CMD")
    parser.add_argument(
        "--capture",
        choices=("auto", "pw-record", "arecord", "ffmpeg", "sox", "cmd"),
        help="capture backend",
    )
    parser.add_argument("--capture-cmd", dest="capture_cmd", metavar="CMD")
    parser.add_argument("--device", help="capture device (backend specific)")
    parser.add_argument("--max-seconds", dest="max_seconds", type=float)
    parser.add_argument(
        "--silence-seconds", dest="silence_seconds", type=float
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="mpd-voice",
        description="Voice control for MPD (local speech recognition).",
    )
    parser.add_argument("--version", action="version", version=__version__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    listen = subparsers.add_parser(
        "listen", help="listen and execute commands"
    )
    listen.add_argument(
        "--once", action="store_true", help="handle exactly one utterance"
    )
    listen.add_argument(
        "--input-wav",
        dest="input_wav",
        metavar="FILE",
        help="transcribe a WAV file instead of the microphone",
    )
    _add_common_options(listen)
    _add_voice_options(listen)

    once = subparsers.add_parser("once", help="alias for `listen --once`")
    once.add_argument("--input-wav", dest="input_wav", metavar="FILE")
    _add_common_options(once)
    _add_voice_options(once)

    say = subparsers.add_parser("say", help="run a typed command")
    say.add_argument("text", nargs="+", help="command words")
    say.add_argument("--speak", action="store_true", help="speak the reply")
    say.add_argument(
        "--dry-run", action="store_true", help="only parse, do not touch MPD"
    )
    _add_common_options(say)
    _add_voice_options(say)

    status = subparsers.add_parser("status", help="show the current song")
    _add_common_options(status)
    _add_voice_options(status)

    parse = subparsers.add_parser("parse", help="show the parsed intent")
    parse.add_argument("text", nargs="+")
    _add_common_options(parse)

    phrases = subparsers.add_parser("phrases", help="list supported phrases")
    _add_common_options(phrases)

    doctor = subparsers.add_parser("doctor", help="check backends and MPD")
    _add_common_options(doctor)
    _add_voice_options(doctor)
    return parser


def _apply_arguments(
    cfg: config_module.Config, args: argparse.Namespace
) -> None:
    overrides = {
        key: value
        for key, value in vars(args).items()
        if key in config_module.Config.__dataclass_fields__
        and value is not None
    }
    cfg.apply_mapping(overrides)


def _client(cfg: config_module.Config, timeout: float = 5.0) -> MPDClient:
    return MPDClient(
        cfg.mpd_host,
        cfg.mpd_port,
        cfg.mpd_password or None,
        timeout=timeout,
    )


def _build_stt(cfg: config_module.Config) -> object:
    return stt_module.build_stt(
        cfg.stt,
        base_url=cfg.stt_url,
        model=cfg.stt_model,
        binary=cfg.stt_bin,
        command=cfg.stt_cmd,
        language=cfg.language,
    )


def _build_tts(cfg: config_module.Config) -> object:
    return tts_module.build_tts(
        cfg.tts,
        base_url=cfg.tts_url,
        voice=cfg.tts_voice,
        command=cfg.tts_cmd,
    )


def _describe_backend(backend: object) -> str:
    """One line describing a resolved backend, for `doctor`."""
    detail = (
        getattr(backend, "base_url", "")
        or getattr(backend, "binary", "")
        or getattr(backend, "command", "")
    )
    return f"{getattr(backend, 'name', '?')} {detail}".strip()


def cmd_say(args: argparse.Namespace, cfg: config_module.Config) -> int:
    text = " ".join(args.text)
    if args.dry_run:
        intent = intents.parse(text)
        payload = asdict(intent)
        payload["understood"] = intent.understood
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        return EXIT_OK if intent.understood else EXIT_UNKNOWN
    reply = Controller(_client(cfg), cfg).handle_text(text)
    print(reply.text)
    if args.speak:
        try:
            _build_tts(cfg).speak(reply.text)
        except tts_module.TTSError as exc:
            print(f"tts: {exc}", file=sys.stderr)
    return EXIT_OK if reply.ok else EXIT_UNKNOWN


def cmd_status(args: argparse.Namespace, cfg: config_module.Config) -> int:
    client = _client(cfg)
    try:
        song = client.current_song()
        status = client.status()
    except (MPDConnectionError, MPDError) as exc:
        print(f"mpd: {exc}", file=sys.stderr)
        return EXIT_ERROR
    if args.json:
        print(
            json.dumps(
                {"status": status, "song": song},
                ensure_ascii=False,
                indent=2,
            )
        )
        return EXIT_OK
    state = status.get("state", "stop")
    if state == "stop" or not song.get("file"):
        print("stopped")
        return EXIT_OK
    print(f"{state}: {describe(song)}")
    return EXIT_OK


def cmd_parse(args: argparse.Namespace, cfg: config_module.Config) -> int:
    intent = intents.parse(" ".join(args.text))
    print(json.dumps(asdict(intent), ensure_ascii=False, indent=2))
    return EXIT_OK if intent.understood else EXIT_UNKNOWN


def cmd_phrases(args: argparse.Namespace, cfg: config_module.Config) -> int:
    for name in sorted(intents.EXAMPLES):
        examples = intents.EXAMPLES[name]
        print(f"{name:16} {' | '.join(examples)}")
    return EXIT_OK


def cmd_doctor(args: argparse.Namespace, cfg: config_module.Config) -> int:
    healthy = True

    client = _client(cfg, timeout=3.0)
    try:
        status = client.status()
        song = client.current_song()
        print(
            f"mpd       ok    {cfg.mpd_host}:{cfg.mpd_port} "
            f"(MPD {client.version}), state={status.get('state', '?')}, "
            f"queue={status.get('playlistlength', '?')}"
        )
        if song.get("file"):
            print(f"          now   {describe(song)}")
    except (MPDConnectionError, MPDError) as exc:
        healthy = False
        print(f"mpd       FAIL  {exc}")

    try:
        backend = audio.detect_backend(cfg.capture, cfg.capture_cmd)
        print(f"capture   ok    {backend}")
    except audio.CaptureError as exc:
        print(f"capture   warn  {exc}")

    try:
        backend = _build_stt(cfg)
        print(f"stt       ok    {_describe_backend(backend)}")
    except stt_module.STTError as exc:
        print(f"stt       warn  {exc}")

    try:
        backend = _build_tts(cfg)
        print(f"tts       ok    {_describe_backend(backend)}")
    except tts_module.TTSError as exc:
        print(f"tts       warn  {exc}")

    _, sources = config_module.load(args.config)
    if sources:
        for source in sources:
            print(f"config    ok    {source}")
    else:
        print("config    warn  no config.toml found (defaults in use)")
    print(f"language  ok    {cfg.language}")
    return EXIT_OK if healthy else EXIT_ERROR


def cmd_listen(args: argparse.Namespace, cfg: config_module.Config) -> int:
    single = getattr(args, "once", False) or getattr(args, "input_wav", None)
    try:
        transcriber = _build_stt(cfg)
    except stt_module.STTError as exc:
        print(f"stt: {exc}", file=sys.stderr)
        return EXIT_ERROR

    speaker = tts_module.NullTTS()
    if cfg.confirm:
        try:
            speaker = _build_tts(cfg)
        except tts_module.TTSError as exc:
            print(f"tts: {exc}", file=sys.stderr)

    recorder = None
    if not getattr(args, "input_wav", None):
        try:
            recorder = audio.Recorder(
                cfg.capture, cfg.device, command=cfg.capture_cmd
            )
        except audio.CaptureError as exc:
            print(f"capture: {exc}", file=sys.stderr)
            return EXIT_ERROR

    controller = Controller(_client(cfg), cfg)
    while True:
        try:
            wav_path = _next_wav(args, cfg, recorder)
        except audio.CaptureError as exc:
            print(f"capture: {exc}", file=sys.stderr)
            return EXIT_ERROR
        if wav_path is None:
            if single:
                return EXIT_OK
            continue
        try:
            transcript = transcriber.transcribe(wav_path, cfg.language)
        except stt_module.STTError as exc:
            print(f"stt: {exc}", file=sys.stderr)
            return EXIT_ERROR
        finally:
            if getattr(args, "input_wav", None) is None:
                wav_path.unlink(missing_ok=True)

        transcript = intents.strip_wake_word(transcript, cfg.wake_word)
        if not transcript:
            # An empty transcript means silence, or speech without the wake
            # word; in one-shot mode that is the end of this run.
            if args.verbose:
                print(
                    "heard nothing"
                    if not cfg.wake_word
                    else f"no wake word ({cfg.wake_word!r})"
                )
            if single:
                return EXIT_UNKNOWN
            continue
        if args.verbose:
            print(f"heard: {transcript}")
        reply = controller.handle_text(transcript)
        print(reply.text)
        try:
            speaker.speak(reply.text)
        except tts_module.TTSError as exc:
            print(f"tts: {exc}", file=sys.stderr)
        if reply.should_exit or single:
            return EXIT_OK if reply.ok else EXIT_UNKNOWN


def _next_wav(
    args: argparse.Namespace,
    cfg: config_module.Config,
    recorder: audio.Recorder | None,
) -> Path | None:
    """Return a WAV to transcribe, or ``None`` when nothing was heard."""
    given = getattr(args, "input_wav", None)
    if given:
        return Path(given)
    assert recorder is not None
    pcm = recorder.capture(cfg.max_seconds, cfg.silence_seconds)
    if not pcm:
        if args.verbose:
            print("capture: no speech detected")
        return None
    handle = tempfile.NamedTemporaryFile(
        prefix="mpd-voice-", suffix=".wav", delete=False
    )
    handle.close()
    return audio.write_wav(handle.name, pcm, recorder.rate)


HANDLERS = {
    "say": cmd_say,
    "status": cmd_status,
    "parse": cmd_parse,
    "phrases": cmd_phrases,
    "doctor": cmd_doctor,
    "listen": cmd_listen,
    "once": cmd_listen,
}


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    cfg, _ = config_module.load(args.config)
    _apply_arguments(cfg, args)
    return HANDLERS[args.command](args, cfg)
