from __future__ import annotations

import argparse
import asyncio
import os
from pathlib import Path

from .server import serve

DEFAULT_ICS_PATHS = tuple(
    path for path in os.environ.get("MCP_AGENDA_ICS_PATHS", "").split(":") if path
)
DEFAULT_NOTES_FILE = os.environ.get("MCP_AGENDA_NOTES_FILE", "~/.local/share/mcp/agenda/notes.json")
DEFAULT_LOOKAHEAD = int(os.environ.get("MCP_AGENDA_LOOKAHEAD_DAYS", "7"))
DEFAULT_TZ = os.environ.get("MCP_AGENDA_TZ", "")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Aggregate calendar feeds and notes into a timeline MCP server",
    )
    parser.add_argument(
        "--ics-paths",
        nargs="*",
        default=DEFAULT_ICS_PATHS,
        help="Directories/files containing ICS events (defaults to env)",
    )
    parser.add_argument(
        "--notes-file",
        default=DEFAULT_NOTES_FILE,
        help="JSON file that stores manual reminders",
    )
    parser.add_argument(
        "--lookahead-days",
        type=int,
        default=DEFAULT_LOOKAHEAD,
        help="Default number of days for upcoming listings",
    )
    parser.add_argument(
        "--timezone",
        default=DEFAULT_TZ,
        help="Override timezone (IANA name)",
    )

    args = parser.parse_args()
    asyncio.run(
        serve(
            ics_paths=list(args.ics_paths) if args.ics_paths else [],
            notes_file=Path(args.notes_file).expanduser(),
            lookahead_days=args.lookahead_days,
            timezone=args.timezone or None,
        )
    )


if __name__ == "__main__":
    main()
