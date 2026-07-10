#!/usr/bin/env python3
"""zen-cookie-write: Write decrypted cookies to a Chromium/Vivaldi Cookies SQLite database.

Reads decrypted JSON from stdin (output of zen-cookie-decrypt.py), transforms
Firefox cookie fields to Chromium schema, and writes atomically to the target
Cookies database.

Usage:
    python3 zen-cookie-read.py --profile /zen/ \\
        | python3 zen-cookie-decrypt.py --profile /zen/ \\
        | python3 zen-cookie-write.py --profile /vivaldi/Default/
"""

import argparse
import json
import os
import sqlite3
import sys
from pathlib import Path


# ── Chromium Cookies table schema ────────────────────────────────────────────

CREATE_TABLE_SQL = """\
CREATE TABLE IF NOT EXISTS cookies(
    creation_utc INTEGER NOT NULL,
    host_key TEXT NOT NULL,
    name TEXT NOT NULL,
    value TEXT NOT NULL,
    path TEXT NOT NULL,
    expires_utc INTEGER NOT NULL,
    is_secure INTEGER NOT NULL,
    is_httponly INTEGER NOT NULL,
    last_access_utc INTEGER NOT NULL DEFAULT 0,
    has_expires INTEGER NOT NULL DEFAULT 1,
    persistent INTEGER NOT NULL DEFAULT 1,
    priority INTEGER NOT NULL DEFAULT 1,
    encrypted_value BLOB DEFAULT '',
    samesite INTEGER NOT NULL DEFAULT -1,
    source_scheme INTEGER NOT NULL DEFAULT 2,
    source_port INTEGER NOT NULL DEFAULT -1,
    is_same_party INTEGER NOT NULL DEFAULT 0,
    UNIQUE(host_key, name, path)
)
"""

INSERT_SQL = """\
INSERT OR REPLACE INTO cookies(
    creation_utc, host_key, name, value, path,
    expires_utc, is_secure, is_httponly, last_access_utc,
    has_expires, persistent, priority, encrypted_value,
    samesite, source_scheme, source_port, is_same_party
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
"""

# WebKit epoch is 1601-01-01 UTC; Unix epoch is 1970-01-01 UTC.
# The offset in seconds between them.
_WEBKIT_UNIX_OFFSET = 11644473600  # seconds


def _to_webkit_time(seconds_since_unix_epoch: float) -> int:
    """Convert Unix epoch seconds to WebKit time (microseconds since 1601-01-01)."""
    return int((seconds_since_unix_epoch + _WEBKIT_UNIX_OFFSET) * 1_000_000)


def _map_samesite(firefox_samesite: int, is_secure: int) -> int:
    """Map Firefox sameSite integer to Chromium sameSite with pair-aware logic.

    Args:
        firefox_samesite: Firefox sameSite value (0=None, 1=Lax, 2=Strict).
        is_secure: Whether the cookie has the Secure flag (0 or 1).

    Returns:
        Chromium sameSite value (-1=UNSPECIFIED, 0=NO_RESTRICTION,
        1=LAX_MODE, 2=STRICT_MODE).
    """
    if firefox_samesite == 1:
        return 1  # LAX
    if firefox_samesite == 2:
        return 2  # STRICT
    if firefox_samesite == 0:
        # NO_RESTRICTION (None) only maps safely when Secure is set
        if is_secure == 1:
            return 0  # NO_RESTRICTION
        return -1  # UNSPECIFIED
    return -1  # UNSPECIFIED fallback


def transform_cookie(cookie: dict) -> tuple:
    """Transform a Firefox cookie dict into a Chromium cookies row tuple.

    Args:
        cookie: Decoded Firefox cookie dict with fields:
            host, name, value, path, expiry, creationTime,
            isSecure, isHttpOnly, sameSite.

    Returns:
        A 17-element tuple matching the INSERT_SQL parameters.
    """
    host_key = cookie.get("host", "").lstrip(".")
    name = cookie.get("name", "")
    value = cookie.get("value", "")
    path = cookie.get("path", "/")

    expiry = cookie.get("expiry", 0)
    creation_time_us = cookie.get("creationTime", 0)

    expires_utc = _to_webkit_time(expiry)
    creation_utc = _to_webkit_time(creation_time_us / 1_000_000)

    is_secure = int(cookie.get("isSecure", 0))
    is_httponly = int(cookie.get("isHttpOnly", 0))
    firefox_samesite = int(cookie.get("sameSite", 0))

    samesite = _map_samesite(firefox_samesite, is_secure)
    has_expires = 1 if expiry > 0 else 0

    return (
        creation_utc,
        host_key,
        name,
        value,
        path,
        expires_utc,
        is_secure,
        is_httponly,
        0,  # last_access_utc
        has_expires,
        1,  # persistent
        1,  # priority
        b"",  # encrypted_value (empty blob — let Chromium re-encrypt)
        samesite,
        2,  # source_scheme
        -1,  # source_port
        0,  # is_same_party
    )


def write_cookies(cookies: list[dict], profile_dir: str) -> int:
    """Write decrypted cookies to the Chromium Cookies database atomically.

    Creates a temporary ``Cookies.new`` SQLite file, inserts all cookies,
    verifies integrity, then atomically renames to ``Cookies``.

    Args:
        cookies: List of decrypted cookie dicts.
        profile_dir: Path to the Vivaldi profile directory.

    Returns:
        Number of successfully written cookies.

    Raises:
        SystemExit: On integrity check failure (exit code 3).
    """
    profile = Path(profile_dir)
    profile.mkdir(parents=True, exist_ok=True)

    db_new_path = str(profile / "Cookies.new")
    db_final_path = str(profile / "Cookies")

    # Remove stale .new file if present from a previous interrupted run
    if os.path.exists(db_new_path):
        os.remove(db_new_path)

    conn = sqlite3.connect(db_new_path)
    try:
        cursor = conn.cursor()
        cursor.execute(CREATE_TABLE_SQL)

        count = 0
        for cookie in cookies:
            row = transform_cookie(cookie)
            cursor.execute(INSERT_SQL, row)
            count += 1

        conn.commit()

        # Integrity check
        cursor.execute("PRAGMA integrity_check")
        result = cursor.fetchone()
        if result is None or result[0] != "ok":
            print(
                f"Error: integrity_check failed — {result}",
                file=sys.stderr,
            )
            conn.close()
            if os.path.exists(db_new_path):
                os.remove(db_new_path)
            sys.exit(3)

    except sqlite3.DatabaseError as exc:
        print(f"Error: database error — {exc}", file=sys.stderr)
        conn.close()
        if os.path.exists(db_new_path):
            os.remove(db_new_path)
        sys.exit(3)

    conn.close()

    # Atomic rename on the same filesystem
    os.rename(db_new_path, db_final_path)

    return count


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Write decrypted cookies to a Chromium/Vivaldi Cookies SQLite database. "
            "Reads a JSON array from stdin (output of zen-cookie-decrypt.py)."
        ),
    )
    parser.add_argument(
        "--profile",
        required=True,
        help="Path to a Vivaldi profile directory (e.g. ~/.config/vivaldi/Default/)",
    )
    args = parser.parse_args()

    # Read and parse JSON from stdin
    raw = sys.stdin.read()
    if not raw.strip():
        print("Error: no input received on stdin", file=sys.stderr)
        sys.exit(1)

    try:
        cookies: list[dict] = json.loads(raw)
    except json.JSONDecodeError as exc:
        print(f"Error: invalid JSON on stdin — {exc}", file=sys.stderr)
        sys.exit(1)

    if not isinstance(cookies, list):
        print("Error: expected a JSON array on stdin", file=sys.stderr)
        sys.exit(1)

    count = write_cookies(cookies, args.profile)

    profile_path = Path(args.profile).resolve()
    print(f"Wrote {count} cookies to {profile_path}/Cookies")
    print(f"VERIFICATION: Cookies written successfully. Row count: {count}")


if __name__ == "__main__":
    main()
