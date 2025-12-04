from __future__ import annotations

import argparse
import asyncio
import os
from pathlib import Path

from .server import serve

DEFAULT_CACHE = Path(os.environ.get("MCP_MEDIA_SEARCH_CACHE", "")).expanduser()
DEFAULT_PATHS = tuple(
    path for path in os.environ.get("MCP_MEDIA_SEARCH_PATHS", "").split(":") if path
)
DEFAULT_TESSERACT = os.environ.get("TESSERACT_BIN", "tesseract")
DEFAULT_OCR_LANG = os.environ.get("MCP_MEDIA_OCR_LANG", "eng")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Index local notes/media and expose them via MCP search tools",
    )
    parser.add_argument(
        "--paths",
        nargs="*",
        default=DEFAULT_PATHS,
        help="Directories to scan (defaults to MCP_MEDIA_SEARCH_PATHS)",
    )
    parser.add_argument(
        "--cache-dir",
        default=str(DEFAULT_CACHE) if DEFAULT_CACHE else None,
        help="Optional cache directory for extracted text",
    )
    parser.add_argument(
        "--tesseract",
        default=DEFAULT_TESSERACT,
        help="Tesseract binary for OCR",
    )
    parser.add_argument(
        "--ocr-lang",
        default=DEFAULT_OCR_LANG,
        help="Languages passed to Tesseract (comma separated)",
    )

    args = parser.parse_args()
    paths = list(args.paths) if args.paths else []
    cache_dir = Path(args.cache_dir).expanduser() if args.cache_dir else None

    asyncio.run(
        serve(
            search_paths=paths,
            cache_dir=cache_dir,
            tesseract_bin=args.tesseract,
            ocr_lang=args.ocr_lang,
        )
    )


if __name__ == "__main__":
    main()
