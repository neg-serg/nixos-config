# agenda-mcp

Agenda MCP server that merges calendar feeds (ICS) and ad-hoc notes to answer questions like "what's
next after 15:00?" or "is there a free hour tomorrow?".

Features:

- Parses multiple `.ics` directories (e.g. Vdirsyncer/Khal) and merges them with a simple JSON
  notes/reminders file.
- Offers listing/search tools for upcoming events and free windows, plus a tool to append
  lightweight notes without touching calendar apps.
- Honors time zones using system defaults (override via env if needed).

Configuration knobs (env vars or CLI flags):

- `MCP_AGENDA_ICS_PATHS` / `--ics-paths`: colon-separated directories/files to scan for ICS data.
- `MCP_AGENDA_NOTES_FILE` / `--notes-file`: path to JSON file that stores manual reminders (created
  automatically if missing).
- `MCP_AGENDA_LOOKAHEAD_DAYS` / `--lookahead-days`: default horizon for `list_upcoming`.
- `MCP_AGENDA_TZ` / `--timezone`: override the local timezone.

The Home Manager module preconfigures sensible defaults so the server works as soon as
Vdirsyncer/Khal directories exist.
