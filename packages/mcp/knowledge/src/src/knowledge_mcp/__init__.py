from __future__ import annotations

import argparse
import asyncio
import os
from pathlib import Path

from .server import serve

DEFAULT_PATHS = tuple(path for path in os.environ.get("MCP_KNOWLEDGE_PATHS", "").split(":") if path)
DEFAULT_CACHE = os.environ.get("MCP_KNOWLEDGE_CACHE", "")
DEFAULT_MODEL = os.environ.get("MCP_KNOWLEDGE_MODEL", "sentence-transformers/all-MiniLM-L6-v2")
DEFAULT_PATTERNS = tuple(
    glob for glob in os.environ.get("MCP_KNOWLEDGE_EXTRA_PATTERNS", "").split(",") if glob
)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Embed local documents and expose vector search tools",
    )
    parser.add_argument("--paths", nargs="*", default=DEFAULT_PATHS)
    parser.add_argument(
        "--cache-dir",
        default=DEFAULT_CACHE,
        help="Cache root for embeddings (metadata.json + vectors.npy)",
    )
    parser.add_argument("--model", default=DEFAULT_MODEL)
    parser.add_argument(
        "--include-globs",
        nargs="*",
        default=DEFAULT_PATTERNS,
        help="Additional glob patterns (beyond defaults) to ingest",
    )

    args = parser.parse_args()
    asyncio.run(
        serve(
            paths=list(args.paths) if args.paths else [],
            cache_dir=Path(args.cache_dir).expanduser() if args.cache_dir else None,
            model_name=args.model,
            include_globs=list(args.include_globs) if args.include_globs else [],
        )
    )


if __name__ == "__main__":
    main()
