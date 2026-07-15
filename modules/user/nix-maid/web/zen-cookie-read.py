#!/usr/bin/env python3
"""zen-cookie-read: Read cookies from a Firefox/Zen Browser cookies.sqlite and output as JSON.

Usage:
    python3 zen-cookie-read.py --profile /path/to/zen/profile

Outputs a JSON array of cookie objects to stdout.
"""

import argparse
import json
import sqlite3
import sys
from binascii import hexlify
from pathlib import Path


def _get_existing_columns(cursor: sqlite3.Cursor) -> set[str]:
    """Query PRAGMA table_info to discover which columns exist in moz_cookies."""
    cursor.execute("PRAGMA table_info(moz_cookies)")
    return {row[1] for row in cursor.fetchall()}


def read_cookies(db_path: str) -> list[dict[str, object]]:
    """Read moz_cookies table and return a list of cookie dicts."""
    db_path_obj = Path(db_path)
    if not db_path_obj.is_file():
        print(
            f"Error: cookies.sqlite not found at: {db_path}", file=sys.stderr
        )
        sys.exit(1)

    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    try:
        cursor = conn.cursor()
        existing = _get_existing_columns(cursor)

        # Build column list from what exists in the schema
        always_columns: list[str] = [
            "name",
            "value",
            "host",
            "path",
            "expiry",
            "creationTime",
            "isSecure",
            "isHttpOnly",
        ]
        selected: list[str] = [c for c in always_columns if c in existing]
        has_same_site = "sameSite" in existing
        has_encrypted = "encryptedValue" in existing
        if has_same_site:
            selected.append("sameSite")
        if has_encrypted:
            selected.append("encryptedValue")

        query = f"SELECT {', '.join(selected)} FROM moz_cookies"
        cursor.execute(query)

        results: list[dict[str, object]] = []
        for row in cursor.fetchall():
            row_dict = dict(zip(selected, row))

            value = row_dict.get("value")
            encrypted = row_dict.get("encryptedValue")
            value_present = value is not None and value != ""
            needs_decryption = not value_present

            out: dict[str, object] = {
                "host": row_dict.get("host") or "",
                "name": row_dict.get("name") or "",
                "value": value if value_present else "",
                "path": row_dict.get("path") or "/",
                "expiry": row_dict.get("expiry") or 0,
                "creationTime": row_dict.get("creationTime") or 0,
                "isSecure": row_dict.get("isSecure") or 0,
                "isHttpOnly": row_dict.get("isHttpOnly") or 0,
                "sameSite": row_dict.get("sameSite") if has_same_site else 0,
                "needs_decryption": needs_decryption,
            }

            if needs_decryption and has_encrypted and encrypted is not None:
                out["encryptedValue"] = (
                    hexlify(encrypted).decode("ascii")
                    if isinstance(encrypted, bytes)
                    else str(encrypted)
                )

            results.append(out)

        return results

    except sqlite3.DatabaseError as e:
        print(f"Error: cannot read cookies.sqlite — {e}", file=sys.stderr)
        sys.exit(1)
    finally:
        conn.close()


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Read cookies from a Firefox/Zen Browser cookies.sqlite "
            "and output them as a JSON array to stdout."
        ),
    )
    parser.add_argument(
        "--profile",
        required=True,
        help="Path to a Firefox/Zen profile directory containing cookies.sqlite",
    )
    args = parser.parse_args()

    db_path = Path(args.profile) / "cookies.sqlite"
    cookies = read_cookies(str(db_path))
    json.dump(cookies, sys.stdout, indent=2, ensure_ascii=False)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
