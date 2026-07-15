#!/usr/bin/env python3
"""Find the equivalent upstream NixOS/nixpkgs commit hash for a given timestamp.

Queries the GitHub Commits API for the nixos-unstable branch at the specified
point in time and returns the commit SHA. Falls back to git ls-remote on
rate-limit (since GitHub no longer redirects /commit/<branch> URLs).
"""

import datetime
import json
import subprocess
import sys
import urllib.error
import urllib.request

TARGET_TIMESTAMP = 1784085041
API_URL = "https://api.github.com/repos/NixOS/nixpkgs/commits"
USER_AGENT = "find-equiv-rev/1.0"


def timestamp_to_iso8601(ts: int) -> str:
    """Convert a Unix timestamp to ISO8601 UTC string."""
    return datetime.datetime.fromtimestamp(
        ts, tz=datetime.timezone.utc
    ).isoformat()


def query_api(until: str) -> str | None:
    """Query GitHub Commits API for the most recent commit before ``until``.

    Returns the commit SHA string, or None on failure.
    """
    url = f"{API_URL}?sha=nixos-unstable&until={until}&per_page=1"
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            if isinstance(data, list) and len(data) > 0:
                return data[0]["sha"]
    except urllib.error.HTTPError as exc:
        print(f"API error: {exc.code} {exc.reason}", file=sys.stderr)
    except (urllib.error.URLError, OSError, json.JSONDecodeError) as exc:
        print(f"Network/parse error: {exc}", file=sys.stderr)
    return None


def fallback_git_ls_remote() -> str | None:
    """Fallback: use ``git ls-remote`` to get the current HEAD of nixos-unstable.

    This gives the tip of the branch rather than the commit at the exact
    timestamp, but it is reliable and does not depend on GitHub API quotas.
    """
    try:
        result = subprocess.run(
            [
                "git",
                "ls-remote",
                "https://github.com/NixOS/nixpkgs.git",
                "refs/heads/nixos-unstable",
            ],
            capture_output=True,
            text=True,
            timeout=30,
        )
    except FileNotFoundError:
        print("error: git not found", file=sys.stderr)
        return None
    except subprocess.TimeoutExpired:
        print("error: git ls-remote timed out", file=sys.stderr)
        return None

    if result.returncode != 0:
        print(
            f"error: git ls-remote failed: {result.stderr.strip()}",
            file=sys.stderr,
        )
        return None

    sha = result.stdout.split(maxsplit=1)[0] if result.stdout.strip() else None
    if sha and len(sha) == 40:
        return sha
    print("error: unexpected git ls-remote output", file=sys.stderr)
    return None


def main() -> None:
    until = timestamp_to_iso8601(TARGET_TIMESTAMP)
    sha = query_api(until)
    if sha is None:
        sha = fallback_git_ls_remote()
    if sha is None:
        sys.exit(1)
    print(sha)


if __name__ == "__main__":
    main()
