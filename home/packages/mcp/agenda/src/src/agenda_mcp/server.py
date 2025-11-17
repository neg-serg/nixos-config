from __future__ import annotations

import json
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path
from typing import Sequence

from dateutil import parser as date_parser
from tzlocal import get_localzone_name
from zoneinfo import ZoneInfo
from ics import Calendar

from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.shared.exceptions import McpError
from mcp.types import TextContent, Tool
from pydantic import BaseModel, Field, ValidationError

ISO_FORMAT = "%Y-%m-%dT%H:%M:%S%z"
DEFAULT_LOOKAHEAD_DAYS = 7


class ListUpcomingInput(BaseModel):
    after: str | None = Field(
        default=None,
        description="ISO timestamp to start from (defaults to now)",
    )
    lookahead_days: int | None = Field(
        default=None,
        ge=1,
        le=60,
        description="Days ahead to include (falls back to server default)",
    )
    limit: int = Field(default=20, ge=1, le=100)


class FreeWindowInput(BaseModel):
    start: str = Field(..., description="ISO timestamp marking search start")
    end: str = Field(..., description="ISO timestamp marking search end")
    duration_minutes: int = Field(..., ge=5, le=24 * 60)
    limit: int = Field(default=5, ge=1, le=20)


class NoteInput(BaseModel):
    title: str = Field(..., min_length=1)
    start: str = Field(..., description="ISO timestamp for note start")
    end: str | None = Field(
        default=None,
        description="Optional ISO end; if omitted, duration_minutes is used",
    )
    duration_minutes: int | None = Field(
        default=None,
        description="Used when end is omitted",
    )
    location: str | None = None
    description: str | None = None


class AgendaEntry(BaseModel):
    id: str
    title: str
    start: str
    end: str
    all_day: bool
    location: str | None = None
    description: str | None = None
    source: str


class WindowResult(BaseModel):
    start: str
    end: str
    duration_minutes: int


@dataclass
class AgendaConfig:
    ics_paths: list[str]
    notes_file: Path
    lookahead_days: int
    timezone: ZoneInfo


class AgendaCatalog:
    def __init__(self, config: AgendaConfig) -> None:
        self.config = config
        self.notes_file = config.notes_file
        self.notes_file.parent.mkdir(parents=True, exist_ok=True)
        self.events = self._load_events()

    def _load_events(self) -> list[AgendaEntry]:
        entries: list[AgendaEntry] = []
        entries.extend(self._load_ics_events())
        entries.extend(self._load_notes())
        entries.sort(key=lambda e: e.start)
        return entries

    def _load_ics_events(self) -> list[AgendaEntry]:
        out: list[AgendaEntry] = []
        seen: set[str] = set()
        for path_str in self.config.ics_paths:
            path = Path(path_str).expanduser()
            if not path.exists():
                continue
            if path.is_file():
                out.extend(self._parse_ics_file(path, seen))
            else:
                for file in path.rglob("*.ics"):
                    out.extend(self._parse_ics_file(file, seen))
        return out

    def _parse_ics_file(self, file: Path, seen: set[str]) -> list[AgendaEntry]:
        try:
            data = file.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            return []
        try:
            calendar = Calendar(data)
        except Exception:
            return []
        entries: list[AgendaEntry] = []
        for event in calendar.events:
            uid = getattr(event, "uid", None) or f"ics:{file}:{event.begin}"
            if uid in seen:
                continue
            seen.add(uid)
            begin = self._normalize_dt(event.begin.datetime)
            end_dt = event.end or event.begin + timedelta(minutes=30)
            end = self._normalize_dt(end_dt.datetime)
            all_day = bool(event.all_day)
            entry = AgendaEntry(
                id=str(uid),
                title=event.name or "(untitled)",
                start=self._fmt(begin),
                end=self._fmt(end),
                all_day=all_day,
                location=event.location,
                description=event.description,
                source=file.as_posix(),
            )
            entries.append(entry)
        return entries

    def _load_notes(self) -> list[AgendaEntry]:
        if not self.notes_file.exists():
            return []
        try:
            payload = json.loads(self.notes_file.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return []
        entries: list[AgendaEntry] = []
        for item in payload if isinstance(payload, list) else []:
            try:
                entry = AgendaEntry(**item)
                entries.append(entry)
            except ValidationError:
                continue
        return entries

    def list_upcoming(
        self, *, after: datetime | None, lookahead_days: int, limit: int
    ) -> list[AgendaEntry]:
        now = after or datetime.now(self.config.timezone)
        horizon = now + timedelta(days=lookahead_days)
        results = [
            entry
            for entry in self.events
            if self._parse(entry.start) >= now and self._parse(entry.start) <= horizon
        ]
        return results[:limit]

    def find_free_windows(
        self, *, start: datetime, end: datetime, duration: timedelta, limit: int
    ) -> list[WindowResult]:
        if end <= start:
            raise McpError("end must be after start")
        busy = self._collect_busy(start, end)
        windows: list[WindowResult] = []
        cursor = start
        for interval_start, interval_end in busy:
            if interval_start - cursor >= duration:
                windows.append(
                    WindowResult(
                        start=self._fmt(cursor),
                        end=self._fmt(interval_start),
                        duration_minutes=int((interval_start - cursor).total_seconds() / 60),
                    )
                )
                if len(windows) >= limit:
                    return windows
            if interval_end > cursor:
                cursor = interval_end
        if end - cursor >= duration and len(windows) < limit:
            windows.append(
                WindowResult(
                    start=self._fmt(cursor),
                    end=self._fmt(end),
                    duration_minutes=int((end - cursor).total_seconds() / 60),
                )
            )
        return windows[:limit]

    def _collect_busy(self, start: datetime, end: datetime) -> list[tuple[datetime, datetime]]:
        intervals: list[tuple[datetime, datetime]] = []
        for entry in self.events:
            s = self._parse(entry.start)
            e = self._parse(entry.end)
            if e <= start or s >= end:
                continue
            intervals.append((max(s, start), min(e, end)))
        intervals.sort(key=lambda pair: pair[0])
        merged: list[tuple[datetime, datetime]] = []
        for interval in intervals:
            if not merged:
                merged.append(interval)
                continue
            last_start, last_end = merged[-1]
            cur_start, cur_end = interval
            if cur_start <= last_end:
                merged[-1] = (last_start, max(last_end, cur_end))
            else:
                merged.append(interval)
        return merged

    def add_note(self, payload: NoteInput) -> AgendaEntry:
        start = self._parse(payload.start)
        if payload.end:
            end = self._parse(payload.end)
        elif payload.duration_minutes:
            end = start + timedelta(minutes=payload.duration_minutes)
        else:
            end = start + timedelta(minutes=30)
        entry = AgendaEntry(
            id=f"note:{uuid.uuid4()}",
            title=payload.title,
            start=self._fmt(start),
            end=self._fmt(end),
            all_day=False,
            location=payload.location,
            description=payload.description,
            source=self.notes_file.as_posix(),
        )
        data = [entry.model_dump() for entry in self._load_notes()]
        data.append(entry.model_dump())
        self.notes_file.write_text(json.dumps(data, indent=2), encoding="utf-8")
        self.events.append(entry)
        self.events.sort(key=lambda e: e.start)
        return entry

    def _normalize_dt(self, dt: datetime) -> datetime:
        if dt.tzinfo is None:
            return dt.replace(tzinfo=self.config.timezone)
        return dt.astimezone(self.config.timezone)

    def _parse(self, value: str) -> datetime:
        dt = date_parser.isoparse(value)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=self.config.timezone)
        return dt.astimezone(self.config.timezone)

    def _fmt(self, dt: datetime) -> str:
        return dt.astimezone(self.config.timezone).strftime(ISO_FORMAT)

    def parse_time(self, value: str) -> datetime:
        return self._parse(value)


async def serve(
    *,
    ics_paths: list[str],
    notes_file: Path,
    lookahead_days: int,
    timezone: str | None,
) -> None:
    tz_name = timezone or get_localzone_name() or "UTC"
    tzinfo = ZoneInfo(tz_name)
    config = AgendaConfig(
        ics_paths=ics_paths,
        notes_file=notes_file,
        lookahead_days=lookahead_days or DEFAULT_LOOKAHEAD_DAYS,
        timezone=tzinfo,
    )
    catalog = AgendaCatalog(config)
    server = Server("agenda")

    schemas = {
        "list": ListUpcomingInput.model_json_schema(),
        "free": FreeWindowInput.model_json_schema(),
        "note": NoteInput.model_json_schema(),
    }

    @server.list_tools()
    async def list_tools() -> list[Tool]:
        return [
            Tool(
                name="list_upcoming",
                description="List upcoming events from calendars and notes",
                inputSchema=schemas["list"],
            ),
            Tool(
                name="find_free_windows",
                description="Find free time windows between start/end",
                inputSchema=schemas["free"],
            ),
            Tool(
                name="add_note_event",
                description="Append a lightweight reminder/note to the agenda",
                inputSchema=schemas["note"],
            ),
        ]

    @server.call_tool()
    async def call_tool(name: str, arguments: dict) -> Sequence[TextContent]:
        try:
            if name == "list_upcoming":
                data = ListUpcomingInput.model_validate(arguments)
                after = date_parser.isoparse(data.after) if data.after else None
                if after and after.tzinfo is None:
                    after = after.replace(tzinfo=config.timezone)
                results = catalog.list_upcoming(
                    after=after.astimezone(config.timezone) if after else None,
                    lookahead_days=data.lookahead_days or config.lookahead_days,
                    limit=data.limit,
                )
                payload = json.dumps([r.model_dump() for r in results], indent=2)
            elif name == "find_free_windows":
                data = FreeWindowInput.model_validate(arguments)
                start = catalog.parse_time(data.start)
                end = catalog.parse_time(data.end)
                windows = catalog.find_free_windows(
                    start=start,
                    end=end,
                    duration=timedelta(minutes=data.duration_minutes),
                    limit=data.limit,
                )
                payload = json.dumps([w.model_dump() for w in windows], indent=2)
            elif name == "add_note_event":
                data = NoteInput.model_validate(arguments)
                entry = catalog.add_note(data)
                payload = entry.model_dump_json(indent=2)
            else:
                raise McpError(f"Unknown tool: {name}")
            return [TextContent(type="text", text=payload)]
        except ValidationError as exc:
            raise McpError(str(exc)) from exc
        except McpError:
            raise
        except Exception as exc:
            raise McpError(str(exc)) from exc

    async with stdio_server() as (read_stream, write_stream):
        options = server.create_initialization_options()
        await server.run(read_stream, write_stream, options)
