"""Allow `python -m mpd_voice`."""

from .cli import main

if __name__ == "__main__":
    raise SystemExit(main())
