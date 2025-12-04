from __future__ import annotations

import argparse
import asyncio
import os

from .server import (
    DEFAULT_MPD_HOST,
    DEFAULT_MPD_PORT,
    DEFAULT_PIPEWIRE_SINK,
    DEFAULT_WPCTL_BIN,
    serve,
)


def main() -> None:
    """Entry point used by the media-mcp console script."""

    env_host = os.environ.get("MCP_MPD_HOST", DEFAULT_MPD_HOST)
    env_port = int(os.environ.get("MCP_MPD_PORT", DEFAULT_MPD_PORT))
    env_sink = os.environ.get("PIPEWIRE_SINK", DEFAULT_PIPEWIRE_SINK)
    env_wpctl = os.environ.get("WPCTL_BIN", DEFAULT_WPCTL_BIN)

    parser = argparse.ArgumentParser(
        description="Expose MPD playback and PipeWire volume controls over MCP",
    )
    parser.add_argument(
        "--mpd-host",
        default=env_host,
        help=f"MPD host (default: {env_host})",
    )
    parser.add_argument(
        "--mpd-port",
        type=int,
        default=env_port,
        help=f"MPD port (default: {env_port})",
    )
    parser.add_argument(
        "--pipewire-sink",
        default=env_sink,
        help=("PipeWire sink/node ID passed to wpctl (default: " f"{env_sink})"),
    )
    parser.add_argument(
        "--wpctl",
        default=env_wpctl,
        help="wpctl binary to call for volume controls",
    )

    args = parser.parse_args()
    asyncio.run(
        serve(
            mpd_host=args.mpd_host,
            mpd_port=args.mpd_port,
            pipewire_sink=args.pipewire_sink,
            wpctl_path=args.wpctl,
        )
    )


if __name__ == "__main__":
    main()
