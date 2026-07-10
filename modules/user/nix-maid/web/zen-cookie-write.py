#!/usr/bin/env python3
# allow: SIZE_OK — single-file Nix script (writeTextFile); encryption, schema,
#        and DB write are an indivisible pipeline; splitting would require a
#        separate Python package beyond scope.

"""zen-cookie-write: Write decrypted cookies to a Vivaldi Cookies SQLite database
with OSCrypt v10 encryption.

Reads decrypted JSON from stdin (output of zen-cookie-decrypt.py), transforms
Firefox cookie fields to Vivaldi 8.0 (Chromium ~130) schema, encrypts values
with OSCrypt v10 (AES-256-GCM), and writes atomically to the target Cookies
database.

Usage:
    python3 zen-cookie-read.py --profile /zen/ \\
        | python3 zen-cookie-decrypt.py --profile /zen/ \\
        | python3 zen-cookie-write.py --profile /vivaldi/Default/ \\
            --local-state /vivaldi/Local\\ State
"""

import argparse
import base64
import hashlib
import json
import os
import sqlite3
import sys
from pathlib import Path

from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.keywrap import aes_key_unwrap, aes_key_wrap


# ── Vivaldi 8.0 (Chromium ~130) Cookies table schema ─────────────────────────

CREATE_COOKIES_SQL = """\
CREATE TABLE IF NOT EXISTS cookies(
    creation_utc INTEGER NOT NULL,
    host_key TEXT NOT NULL,
    top_frame_site_key TEXT NOT NULL DEFAULT '',
    name TEXT NOT NULL,
    value TEXT NOT NULL,
    encrypted_value BLOB NOT NULL,
    path TEXT NOT NULL,
    expires_utc INTEGER NOT NULL,
    is_secure INTEGER NOT NULL,
    is_httponly INTEGER NOT NULL,
    last_access_utc INTEGER NOT NULL DEFAULT 0,
    has_expires INTEGER NOT NULL DEFAULT 1,
    is_persistent INTEGER NOT NULL DEFAULT 1,
    priority INTEGER NOT NULL DEFAULT 1,
    samesite INTEGER NOT NULL DEFAULT -1,
    source_scheme INTEGER NOT NULL DEFAULT 2,
    source_port INTEGER NOT NULL DEFAULT -1,
    last_update_utc INTEGER NOT NULL DEFAULT 0,
    source_type INTEGER NOT NULL DEFAULT 0,
    has_cross_site_ancestor INTEGER NOT NULL DEFAULT 0
)
"""

CREATE_COOKIES_UNIQUE_SQL = """\
CREATE UNIQUE INDEX IF NOT EXISTS cookies_unique_index
    ON cookies(host_key, top_frame_site_key, has_cross_site_ancestor,
               name, path, source_scheme, source_port)
"""

CREATE_META_SQL = """\
CREATE TABLE IF NOT EXISTS meta(
    key LONGVARCHAR NOT NULL UNIQUE PRIMARY KEY,
    value LONGVARCHAR NOT NULL
)
"""

INSERT_COOKIE_SQL = """\
INSERT OR REPLACE INTO cookies(
    creation_utc, host_key, top_frame_site_key, name, value,
    encrypted_value, path, expires_utc, is_secure, is_httponly,
    last_access_utc, has_expires, is_persistent, priority, samesite,
    source_scheme, source_port, last_update_utc, source_type,
    has_cross_site_ancestor
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
"""

INSERT_META_SQL = "INSERT OR REPLACE INTO meta(key, value) VALUES(?, ?)"

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
        return 1  # LAX_MODE
    if firefox_samesite == 2:
        return 2  # STRICT_MODE
    if firefox_samesite == 0:
        # NO_RESTRICTION (None) only maps safely when Secure is set
        return 0 if is_secure else -1
    return -1  # UNSPECIFIED fallback


# ── OSCrypt v10 encryption helpers ───────────────────────────────────────────

_OSCRYPT_FIXED = b"peanuts"


def _derive_wrapping_key() -> bytes:
    """Derive the 16-byte AES-128 key-wrap key from Chromium's fixed string.

    Chromium OSCrypt v10 uses ``SHA-256("peanuts")[:16]`` as the RFC 3394
    AES Key Wrap key that protects the encryption master key in Local State.
    """
    return hashlib.sha256(_OSCRYPT_FIXED).digest()[:16]


def _generate_encryption_key() -> tuple[bytes, str]:
    """Generate a fresh 32-byte AES-256 key, wrapped in OSCrypt v10 format.

    Returns:
        Tuple of ``(raw_key, base64_encoded_stored_key)``.

    The stored key format is::

        base64("v10" + AES_KW(wrapping_key, raw_key))

    where ``wrapping_key = SHA-256("peanuts")[:16]``.
    """
    raw_key = os.urandom(32)
    wrapping_key = _derive_wrapping_key()
    wrapped = aes_key_wrap(wrapping_key, raw_key)
    stored_key = base64.b64encode(b"v10" + wrapped).decode("ascii")
    return raw_key, stored_key


def _load_or_create_encryption_key(local_state_path: str) -> bytes:
    """Load existing or create new OSCrypt v10 encryption key in Local State.

    Reads ``os_crypt.encrypted_key`` from the Vivaldi ``Local State`` JSON
    file.  If the key already exists, it is unwrapped and returned.
    Otherwise a fresh 32-byte key is generated, wrapped with AES-128 Key
    Wrap (RFC 3394), written to ``Local State``, and returned.

    The ``portal`` entry in ``os_crypt`` is preserved if present; a default
    is created only when the entire ``os_crypt`` section is absent.

    Returns:
        The 32-byte raw AES-256 key for cookie encryption.

    Raises:
        SystemExit: On Local State read/write failures or key errors.
    """
    ls_path = Path(local_state_path)
    ls_data: dict = {}

    # Load existing Local State if present and non-empty
    if ls_path.exists() and ls_path.stat().st_size > 0:
        try:
            ls_data = json.loads(ls_path.read_text("utf-8"))
        except (json.JSONDecodeError, OSError) as exc:
            print(f"Error: Failed to read Local State at {ls_path} — {exc}", file=sys.stderr)
            sys.exit(4)

    # Ensure os_crypt section exists
    if "os_crypt" not in ls_data:
        ls_data["os_crypt"] = {}
    os_crypt = ls_data["os_crypt"]

    # ── Reuse existing encrypted_key ─────────────────────────────────────────
    if "encrypted_key" in os_crypt and os_crypt["encrypted_key"]:
        stored = os_crypt["encrypted_key"]
        try:
            decoded = base64.b64decode(stored)
        except Exception as exc:
            print(f"Error: Failed to decode os_crypt.encrypted_key — {exc}", file=sys.stderr)
            sys.exit(5)

        if not decoded.startswith(b"v10"):
            print(
                "Error: Unsupported OSCrypt version in encrypted_key "
                f"(expected 'v10', got {decoded[:3]!r})",
                file=sys.stderr,
            )
            sys.exit(5)

        wrapped = decoded[3:]  # strip "v10" prefix (3 bytes)
        wrapping_key = _derive_wrapping_key()
        try:
            raw_key = aes_key_unwrap(wrapping_key, wrapped)
        except Exception as exc:
            print(f"Error: Failed to unwrap encryption key — {exc}", file=sys.stderr)
            sys.exit(5)

        if len(raw_key) != 32:
            print(
                f"Error: Unexpected unwrapped key length {len(raw_key)} "
                f"(expected 32)",
                file=sys.stderr,
            )
            sys.exit(5)

        # Remove portal entry to force Vivaldi to use encrypted_key
        if "portal" in os_crypt:
            del os_crypt["portal"]
            # Write back updated Local State
            try:
                tmp_path = ls_path.with_name(ls_path.name + ".tmp")
                tmp_path.write_text(json.dumps(ls_data, indent=2), "utf-8")
                tmp_path.rename(ls_path)
            except OSError as exc:
                print(f"Error: Failed to write Local State — {exc}", file=sys.stderr)
                sys.exit(4)

        return raw_key

    # ── Generate new key ─────────────────────────────────────────────────────
    raw_key, stored_key = _generate_encryption_key()
    os_crypt["encrypted_key"] = stored_key

    # Remove portal entry to force Vivaldi to use encrypted_key mode.
    # Vivaldi 8.0 prefers portal-based encryption, but on Hyprland
    # portal init fails (prev_init_success: false). If portal is present,
    # Vivaldi keeps trying it and ignores encrypted_key entirely.
    if "portal" in os_crypt:
        del os_crypt["portal"]

    # Write Local State atomically (temp file + rename)
    try:
        ls_path.parent.mkdir(parents=True, exist_ok=True)
        tmp_path = ls_path.with_name(ls_path.name + ".tmp")
        tmp_path.write_text(json.dumps(ls_data, indent=2), "utf-8")
        tmp_path.rename(ls_path)
    except OSError as exc:
        print(f"Error: Failed to write Local State to {ls_path} — {exc}", file=sys.stderr)
        sys.exit(4)

    return raw_key


def encrypt_cookie_value(plaintext: str, key: bytes) -> bytes:
    """Encrypt a cookie value using OSCrypt v10 (AES-256-GCM).

    Format::

        v10 (2 bytes) + nonce (12 bytes) + ciphertext+tag (variable)

    The GCM authentication tag (16 bytes) is appended by the ``AESGCM``
    implementation automatically.

    Args:
        plaintext: The cookie value to encrypt.
        key: The 32-byte AES-256 key.

    Returns:
        The v10-encrypted blob ready for ``encrypted_value``.
    """
    nonce = os.urandom(12)
    aesgcm = AESGCM(key)
    ciphertext = aesgcm.encrypt(nonce, plaintext.encode("utf-8"), None)
    return b"v10" + nonce + ciphertext


# ── Cookie transformation ────────────────────────────────────────────────────


def transform_cookie(cookie: dict, enc_key: bytes) -> tuple:
    """Transform a Firefox cookie dict into a Vivaldi cookies row tuple.

    Args:
        cookie: Decoded Firefox cookie dict with fields:
            host, name, value, path, expiry, creationTime,
            isSecure, isHttpOnly, sameSite.
        enc_key: The 32-byte AES-256 key for value encryption.

    Returns:
        A 20-element tuple matching ``INSERT_COOKIE_SQL`` parameters.
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

    # Encrypt the cookie value using OSCrypt v10
    encrypted_value = encrypt_cookie_value(value, enc_key)

    # Column order matches INSERT_COOKIE_SQL.
    # Note: Chromium stores both value (plaintext, backwards compat) and
    #       encrypted_value (v10 ciphertext, authoritative).
    return (
        creation_utc,
        host_key,
        "",  # top_frame_site_key (no CHIPS support needed)
        name,
        value,  # plaintext (fallback for older Chromium versions)
        encrypted_value,  # OSCrypt v10 AES-256-GCM blob
        path,
        expires_utc,
        is_secure,
        is_httponly,
        creation_utc,  # last_access_utc (initialised to creation time)
        has_expires,
        1,  # is_persistent
        1,  # priority
        samesite,
        2,  # source_scheme (Scheme::kStandard = 2)
        -1,  # source_port (-1 = unknown/unset)
        creation_utc,  # last_update_utc
        0,  # source_type (0 = kFirstParty)
        0,  # has_cross_site_ancestor
    )


# ── Database write ───────────────────────────────────────────────────────────


def write_cookies(
    cookies: list[dict],
    profile_dir: str,
    enc_key: bytes,
) -> int:
    """Write decrypted cookies to a Vivaldi Cookies database atomically.

    Creates a temporary ``Cookies.new`` SQLite file with the full Vivaldi 8.0
    schema (20 columns + ``meta`` table), encrypts each cookie value with
    OSCrypt v10, inserts all cookies, verifies integrity, then atomically
    renames to ``Cookies``.

    Args:
        cookies: List of decrypted cookie dicts.
        profile_dir: Path to Vivaldi profile directory.
        enc_key: 32-byte AES-256-GCM encryption key.

    Returns:
        Number of cookies written.

    Raises:
        SystemExit: On integrity check failure (exit code 3) or DB error.
    """
    profile = Path(profile_dir)
    profile.mkdir(parents=True, exist_ok=True)

    db_new = str(profile / "Cookies.new")
    db_final = str(profile / "Cookies")

    # Remove stale .new file from a previous interrupted run
    if os.path.exists(db_new):
        os.remove(db_new)

    conn = sqlite3.connect(db_new)
    try:
        cursor = conn.cursor()

        # Create tables, index, and meta version
        cursor.execute(CREATE_COOKIES_SQL)
        cursor.execute(CREATE_COOKIES_UNIQUE_SQL)
        cursor.execute(CREATE_META_SQL)
        cursor.execute(INSERT_META_SQL, ("version", "1"))

        # Insert all cookies with encrypted values
        count = 0
        for cookie in cookies:
            row = transform_cookie(cookie, enc_key)
            cursor.execute(INSERT_COOKIE_SQL, row)
            count += 1

        conn.commit()

        # Integrity check — abort if not pristine
        cursor.execute("PRAGMA integrity_check")
        result = cursor.fetchone()
        if result is None or result[0] != "ok":
            print(
                f"Error: integrity_check failed — {result}",
                file=sys.stderr,
            )
            conn.close()
            if os.path.exists(db_new):
                os.remove(db_new)
            sys.exit(3)

    except sqlite3.DatabaseError as exc:
        print(f"Error: Database error — {exc}", file=sys.stderr)
        conn.close()
        if os.path.exists(db_new):
            os.remove(db_new)
        sys.exit(3)

    conn.close()

    # Atomic rename on the same filesystem
    os.rename(db_new, db_final)

    return count


# ── Main ─────────────────────────────────────────────────────────────────────


def resolve_local_state(profile_dir: str) -> str:
    """Derive Local State path from a profile directory.

    Chromium-based browsers store ``Local State`` in the user-data directory,
    one level above the profile directory::

        ~/.config/vivaldi/Default/  →  ~/.config/vivaldi/Local State
    """
    profile = Path(profile_dir).resolve()
    return str(profile.parent / "Local State")


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Write decrypted cookies to a Vivaldi Cookies database with "
            "OSCrypt v10 encryption (AES-256-GCM). Reads a JSON array from stdin."
        ),
    )
    parser.add_argument(
        "--profile",
        required=True,
        help="Path to a Vivaldi profile directory (e.g. ~/.config/vivaldi/Default/)",
    )
    parser.add_argument(
        "--local-state",
        default=None,
        help=(
            "Path to Vivaldi's Local State file. "
            "Default: ``<profile_parent>/Local State``"
        ),
    )
    args = parser.parse_args()

    # Resolve Local State path
    local_state = args.local_state or resolve_local_state(args.profile)

    # Read and parse JSON array from stdin
    raw = sys.stdin.read()
    if not raw.strip():
        print("Error: No input received on stdin", file=sys.stderr)
        sys.exit(1)

    try:
        cookies: list[dict] = json.loads(raw)
    except json.JSONDecodeError as exc:
        print(f"Error: Invalid JSON on stdin — {exc}", file=sys.stderr)
        sys.exit(1)

    if not isinstance(cookies, list):
        print("Error: Expected a JSON array on stdin", file=sys.stderr)
        sys.exit(1)

    # Load or generate the OSCrypt v10 encryption key (stored in Local State)
    enc_key = _load_or_create_encryption_key(local_state)

    # Write cookies with OSCrypt v10 encryption
    count = write_cookies(cookies, args.profile, enc_key)

    profile_path = Path(args.profile).resolve()
    print(
        f"Wrote {count} cookies to {profile_path}/Cookies "
        f"(encrypted with v10, key stored in Local State)"
    )


if __name__ == "__main__":
    main()
