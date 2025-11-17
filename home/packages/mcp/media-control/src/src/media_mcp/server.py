from __future__ import annotations

import re
import subprocess
from contextlib import contextmanager
from dataclasses import dataclass
from enum import Enum
from typing import Sequence

from mpd import MPDClient
from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.shared.exceptions import McpError
from mcp.types import Tool, TextContent
from pydantic import BaseModel, Field, ValidationError

DEFAULT_MPD_HOST = "localhost"
DEFAULT_MPD_PORT = 6600
DEFAULT_PIPEWIRE_SINK = "@DEFAULT_AUDIO_SINK@"
DEFAULT_WPCTL_BIN = "wpctl"


class ToolNames(str, Enum):
    GET_STATUS = "get_playback_status"
    CONTROL = "control_playback"
    QUEUE_ARTIST = "queue_artist"
    ADJUST_VOLUME = "adjust_volume"


class PlaybackStatus(BaseModel):
    state: str
    artist: str | None = None
    album: str | None = None
    title: str | None = None
    elapsed_seconds: float | None = None
    duration_seconds: float | None = None
    queue_length: int | None = None
    volume_percent: int | None = None
    repeat: bool | None = None
    random: bool | None = None


class PlaybackControlInput(BaseModel):
    action: str = Field(
        description="Supported actions: play, pause, toggle, next, previous, stop, clear",
    )


class QueueArtistInput(BaseModel):
    artist: str = Field(..., min_length=1, description="Artist name to search for")
    clear_queue: bool = Field(
        default=False,
        description="Clear the queue before adding tracks",
    )
    play_immediately: bool = Field(
        default=False,
        description="Start playback right after queueing (if tracks were added)",
    )


class VolumeInput(BaseModel):
    action: str = Field(
        description="Volume actions: set, change, mute, unmute, toggle",
    )
    level: float | None = Field(
        default=None,
        ge=0.0,
        le=1.0,
        description="Absolute level (0.0-1.0) for the 'set' action",
    )
    delta: float | None = Field(
        default=None,
        description="Relative adjustment (-0.5..0.5) for the 'change' action",
    )
    sink: str | None = Field(
        default=None,
        description="PipeWire sink/node ID (defaults to @DEFAULT_AUDIO_SINK@)",
    )


class QueueArtistResult(BaseModel):
    artist: str
    queued_tracks: int
    cleared_queue: bool
    started_playback: bool


class VolumeResult(BaseModel):
    sink: str
    level: float
    percent: int
    muted: bool


@dataclass
class ControllerConfig:
    mpd_host: str = DEFAULT_MPD_HOST
    mpd_port: int = DEFAULT_MPD_PORT
    wpctl_path: str = DEFAULT_WPCTL_BIN
    pipewire_sink: str = DEFAULT_PIPEWIRE_SINK


def clamp(value: float, *, lower: float = 0.0, upper: float = 1.0) -> float:
    return max(lower, min(upper, value))


class MediaController:
    def __init__(self, config: ControllerConfig) -> None:
        self.config = config

    @contextmanager
    def _client(self) -> MPDClient:
        client = MPDClient()
        client.timeout = 3
        client.idletimeout = None
        client.connect(self.config.mpd_host, self.config.mpd_port)
        try:
            yield client
        finally:
            try:
                client.close()
            except Exception:
                pass
            try:
                client.disconnect()
            except Exception:
                pass

    def get_status(self) -> PlaybackStatus:
        with self._client() as client:
            status = client.status()
            song = client.currentsong()

        return PlaybackStatus(
            state=status.get("state", "unknown"),
            artist=song.get("artist"),
            album=song.get("album"),
            title=song.get("title"),
            elapsed_seconds=_safe_float(status.get("elapsed")),
            duration_seconds=_safe_float(song.get("duration") or status.get("duration")),
            queue_length=_safe_int(status.get("playlistlength")),
            volume_percent=_safe_int(status.get("volume")),
            repeat=_safe_bool(status.get("repeat")),
            random=_safe_bool(status.get("random")),
        )

    def control_playback(self, action: str) -> None:
        normalized = action.strip().lower()
        with self._client() as client:
            match normalized:
                case "play":
                    client.play()
                case "pause":
                    client.pause(1)
                case "toggle":
                    state = client.status().get("state")
                    if state == "play":
                        client.pause(1)
                    else:
                        client.play()
                case "next":
                    client.next()
                case "previous":
                    client.previous()
                case "stop":
                    client.stop()
                case "clear":
                    client.clear()
                case _:
                    raise McpError(f"Unsupported playback action: {action}")

    def queue_artist(self, payload: QueueArtistInput) -> QueueArtistResult:
        with self._client() as client:
            if payload.clear_queue:
                client.clear()

            matches = client.find("artist", payload.artist)
            files = [entry.get("file") for entry in matches if entry.get("file")]
            if not files:
                raise McpError(f"No tracks found for artist '{payload.artist}'")

            for song in files:
                client.add(song)

            started = False
            if payload.play_immediately:
                client.play()
                started = True

        return QueueArtistResult(
            artist=payload.artist,
            queued_tracks=len(files),
            cleared_queue=payload.clear_queue,
            started_playback=started,
        )

    def adjust_volume(self, payload: VolumeInput) -> VolumeResult:
        sink = payload.sink or self.config.pipewire_sink
        action = payload.action.strip().lower()

        if not self.config.wpctl_path:
            raise McpError("wpctl binary is not configured")

        if action == "set":
            if payload.level is None:
                raise McpError("level is required for the 'set' action")
            target_level = clamp(payload.level)
            self._run_wpctl(["set-volume", sink, f"{target_level:.4f}"])
        elif action == "change":
            if payload.delta is None:
                raise McpError("delta is required for the 'change' action")
            info = self._get_volume(sink)
            target_level = clamp(info.level + payload.delta)
            self._run_wpctl(["set-volume", sink, f"{target_level:.4f}"])
        elif action == "mute":
            self._run_wpctl(["set-mute", sink, "1"])
        elif action == "unmute":
            self._run_wpctl(["set-mute", sink, "0"])
        elif action == "toggle":
            self._run_wpctl(["set-mute", sink, "toggle"])
        else:
            raise McpError(f"Unsupported volume action: {payload.action}")

        return self._get_volume(sink)

    def _run_wpctl(self, args: list[str]) -> str:
        try:
            proc = subprocess.run(
                [self.config.wpctl_path, *args],
                capture_output=True,
                text=True,
                check=True,
            )
            return proc.stdout.strip()
        except FileNotFoundError as exc:
            raise McpError(f"wpctl not found at {self.config.wpctl_path}") from exc
        except subprocess.CalledProcessError as exc:
            raise McpError(exc.stderr.strip() or exc.stdout.strip() or str(exc)) from exc

    def _get_volume(self, sink: str) -> VolumeResult:
        output = self._run_wpctl(["get-volume", sink])
        return _parse_volume_output(output, sink)


def _safe_float(value: str | None) -> float | None:
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _safe_int(value: str | None) -> int | None:
    if value is None:
        return None
    try:
        return int(float(value))
    except (TypeError, ValueError):
        return None


def _safe_bool(value: str | None) -> bool | None:
    if value is None:
        return None
    return value in {"1", "true", "True"}


_VOLUME_RE = re.compile(r"Volume:\s*([0-9.]+)")
_MUTED_RE = re.compile(r"mute", re.IGNORECASE)


def _parse_volume_output(output: str, sink: str) -> VolumeResult:
    match = _VOLUME_RE.search(output)
    if not match:
        raise McpError(f"Unable to parse wpctl volume output: '{output}'")

    level = clamp(float(match.group(1)))
    percent = int(round(level * 100))
    muted = bool(_MUTED_RE.search(output))
    return VolumeResult(sink=sink, level=level, percent=percent, muted=muted)


async def serve(
    *,
    mpd_host: str = DEFAULT_MPD_HOST,
    mpd_port: int = DEFAULT_MPD_PORT,
    pipewire_sink: str = DEFAULT_PIPEWIRE_SINK,
    wpctl_path: str = DEFAULT_WPCTL_BIN,
) -> None:
    config = ControllerConfig(
        mpd_host=mpd_host,
        mpd_port=mpd_port,
        pipewire_sink=pipewire_sink,
        wpctl_path=wpctl_path,
    )
    controller = MediaController(config)
    server = Server("media-control")

    schemas = {
        ToolNames.CONTROL.value: PlaybackControlInput.model_json_schema(),
        ToolNames.QUEUE_ARTIST.value: QueueArtistInput.model_json_schema(),
        ToolNames.ADJUST_VOLUME.value: VolumeInput.model_json_schema(),
    }

    @server.list_tools()
    async def list_tools() -> list[Tool]:
        return [
            Tool(
                name=ToolNames.GET_STATUS.value,
                description="Return MPD playback status (track, artist, queue, state)",
            ),
            Tool(
                name=ToolNames.CONTROL.value,
                description="Control MPD playback (play, pause, toggle, next, etc.)",
                inputSchema=schemas[ToolNames.CONTROL.value],
            ),
            Tool(
                name=ToolNames.QUEUE_ARTIST.value,
                description="Queue every track that matches the requested artist",
                inputSchema=schemas[ToolNames.QUEUE_ARTIST.value],
            ),
            Tool(
                name=ToolNames.ADJUST_VOLUME.value,
                description="Adjust PipeWire sink volume using wpctl",
                inputSchema=schemas[ToolNames.ADJUST_VOLUME.value],
            ),
        ]

    @server.call_tool()
    async def call_tool(name: str, arguments: dict) -> Sequence[TextContent]:
        try:
            match name:
                case ToolNames.GET_STATUS.value:
                    result = controller.get_status()
                case ToolNames.CONTROL.value:
                    payload = PlaybackControlInput.model_validate(arguments)
                    controller.control_playback(payload.action)
                    result = controller.get_status()
                case ToolNames.QUEUE_ARTIST.value:
                    payload = QueueArtistInput.model_validate(arguments)
                    result = controller.queue_artist(payload)
                case ToolNames.ADJUST_VOLUME.value:
                    payload = VolumeInput.model_validate(arguments)
                    result = controller.adjust_volume(payload)
                case _:
                    raise McpError(f"Unknown tool: {name}")

            return [
                TextContent(type="text", text=result.model_dump_json(indent=2)),
            ]
        except ValidationError as exc:
            raise McpError(str(exc)) from exc
        except McpError:
            raise
        except Exception as exc:
            raise McpError(str(exc)) from exc

    async with stdio_server() as (read_stream, write_stream):
        options = server.create_initialization_options()
        await server.run(read_stream, write_stream, options)
