# home/run

Ephemeral runtime scratchpad for MCP experiments and container state. Everything under `home/run/tmp/` or `home/run/libpod/` is intentionally ignored by Git so large third-party checkouts and build artifacts never sneak into commits.

Use `nix build` and the packages under `packages/mcp` instead of keeping vendored sources here. When you really need to stage temporary sources, drop them under `home/run/tmp/` and delete them afterwards.
