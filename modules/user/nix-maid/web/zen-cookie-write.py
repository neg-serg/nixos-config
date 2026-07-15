#!/usr/bin/env python3
# allow: SIZE_OK — single-file Nix script (writeShellApplication); encryption,
#        schema, and DB write are an indivisible pipeline; splitting would
#        require a separate Python package beyond scope.

"""zen-cookie-write: Write decrypted cookies to a Vivaldi Cookies SQLite database
with OSCrypt v11 encryption (AES-128-CBC, PBKDF2-derived key).

Reads decrypted JSON from stdin (output of zen-cookie-decrypt.py), transforms
Firefox cookie fields to Vivaldi 8.0 (Chromium ~130) schema, encrypts values
with OSCrypt v11 (AES-128-CBC, PKCS7 padding, static IV) using a 16-byte key
derived via PBKDF2-HMAC-SHA1 from the 32-byte seed in gnome-keyring, and
writes atomically to the target Cookies database.

The 32-byte encryption seed is stored in gnome-keyring (Chrome Safe Storage)
ONLY — Local State's ``encrypted_key`` and ``portal`` sections are removed
so Vivaldi discovers the key itself from gnome-keyring, avoiding portal
conflicts that can delete cookies on restart.

Usage:
    python3 zen-cookie-read.py --profile /zen/ \\
        | python3 zen-cookie-decrypt.py --profile /zen/ \\
        | python3 zen-cookie-write.py --profile /vivaldi/Default/
"""

import argparse
import base64
import json
import os
import sqlite3
import subprocess
import sys
from pathlib import Path

from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives import padding, hashes
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC


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
    if firefox_samesite == 256:
        return -1  # UNSPECIFIED (Firefox default when omitted)
    if firefox_samesite == 1:
        return 1  # LAX_MODE
    if firefox_samesite == 2:
        return 2  # STRICT_MODE
    if firefox_samesite == 0:
        # NO_RESTRICTION (None) only maps safely when Secure is set
        return 0 if is_secure else -1
    return -1  # UNSPECIFIED fallback


# ── Gnome-keyring helpers ──────────────────────────────────────────────────

# Attribute sets to try when looking up the key in gnome-keyring, in order
# of specificity. Vivaldi 8.0 stores the key under "Chrome Safe Storage"
# with ``application=vivaldi`` and one of several possible schema attributes.
_KEYRING_ATTR_SETS: list[list[str]] = [
    ["application", "vivaldi", "xdg:schema", "org.chromium.Chromium"],
    [
        "application",
        "vivaldi",
        "xdg:schema",
        "chrome_libsecret_os_crypt_password_v2",
    ],
    ["application", "vivaldi"],
    ["xdg:schema", "org.chromium.Chromium"],
    ["xdg:schema", "chrome_libsecret_os_crypt_password_v2"],
]


def _get_secret_from_keyring() -> bytes | None:
    """Read the raw OSCrypt secret from gnome-keyring.

    Vivaldi / Chromium stores the OSCrypt encryption key (typically 32 bytes)
    in gnome-keyring under the ``Chrome Safe Storage`` label.

    Returns:
        The raw secret bytes if found, ``None`` otherwise.
    """
    for attrs in _KEYRING_ATTR_SETS:
        try:
            result = subprocess.run(
                ["secret-tool", "lookup", *attrs],
                capture_output=True,
                timeout=5,
            )
        except (FileNotFoundError, subprocess.TimeoutExpired, OSError):
            continue

        if result.returncode != 0 or not result.stdout:
            continue

        secret_data = result.stdout.rstrip(b"\n\r")

        # Try base64 decoding first (common Chromium storage format);
        # if it fails, treat as raw bytes.
        try:
            return base64.b64decode(secret_data)
        except Exception:
            return secret_data

    return None


def _store_secret_in_keyring(secret: bytes) -> bool:
    """Store a raw OSCrypt secret in gnome-keyring.

    Uses the same schema as Vivaldi/Chromium:
        Label: ``Chrome Safe Storage``
        Attributes: ``application=vivaldi``, ``xdg:schema=org.chromium.Chromium``

    The secret is stored as raw bytes (not base64-encoded) for maximum
    compatibility with Chromium's own keyring read.

    Returns:
        ``True`` if stored successfully, ``False`` otherwise.
    """
    try:
        result = subprocess.run(
            [
                "secret-tool",
                "store",
                "--label",
                "Chrome Safe Storage",
                "application",
                "vivaldi",
                "xdg:schema",
                "org.chromium.Chromium",
            ],
            input=secret,
            capture_output=True,
            timeout=5,
        )
        return result.returncode == 0
    except (FileNotFoundError, subprocess.TimeoutExpired, OSError):
        return False


def _load_or_create_encryption_key(local_state_path: str) -> bytes:
    """Load or create the OSCrypt 32-byte encryption seed key.

    Vivaldi / Chromium OSCrypt v11 uses PBKDF2 to derive a 16-byte AES-128
    key from a 32-byte seed. The seed is stored in gnome-keyring ONLY;
    Local State's ``encrypted_key`` and ``portal`` sections are removed
    so Vivaldi discovers the key itself from gnome-keyring.

    Resolution order:

    1. **Gnome-keyring** – Look up the secret under ``Chrome Safe Storage``.
       If found, clean up Local State (remove portal + encrypted_key) and
       return the key.
    2. **Generate new** – Create a fresh 32-byte random key, store it in
       gnome-keyring with the proper Vivaldi attributes, clean up Local
       State, and return the key.

    Args:
        local_state_path: Path to Vivaldi's ``Local State`` JSON file.
            Portal and ``encrypted_key`` entries are removed from it
            to let Vivaldi discover the key from gnome-keyring.

    Returns:
        The 32-byte OSCrypt seed key.

    Raises:
        SystemExit: On keyring storage failure (exit code 5).
    """
    # ── Step 1: Gnome-keyring ───────────────────────────────────────────────
    secret = _get_secret_from_keyring()
    if secret is not None:
        # Use the raw secret as the 32-byte key (no PBKDF2 derivation)
        _write_key_to_local_state(local_state_path, secret)
        return secret

    # ── Step 2: Generate new key ─────────────────────────────────────────────
    new_key = os.urandom(32)
    if not _store_secret_in_keyring(new_key):
        print(
            "Error: Failed to store new OSCrypt seed key in gnome-keyring",
            file=sys.stderr,
        )
        sys.exit(5)

    _write_key_to_local_state(local_state_path, new_key)
    return new_key


def _write_key_to_local_state(local_state_path: str, raw_key: bytes) -> None:
    """Remove portal and encrypted_key from Local State.

    The key is already stored in gnome-keyring by ``_store_secret_in_keyring``.
    Vivaldi will discover it from gnome-keyring on first startup and create
    its own ``encrypted_key`` entry.  We must NOT write ``encrypted_key``
    ourselves — if we do, Vivaldi may prefer the portal path and fall into
    a state where cookies are deleted on every restart.

    Removing both ``portal`` and ``encrypted_key`` ensures Vivaldi starts
    fresh: it creates portal (``prev_init_success: False`` → portal fails
    on Hyprland), falls back to gnome-keyring, finds our key, and writes
    ``encrypted_key`` itself — with the *same* key we used for encryption.

    Args:
        local_state_path: Path to Vivaldi's ``Local State`` JSON file.
        raw_key: The raw 32-byte seed key (unused — key is in gnome-keyring).
    """
    ls_path = Path(local_state_path)
    if not ls_path.exists() or ls_path.stat().st_size == 0:
        return

    try:
        ls_data = json.loads(ls_path.read_text("utf-8"))
    except (json.JSONDecodeError, OSError):
        return

    if "os_crypt" not in ls_data:
        return

    changed = False
    if "portal" in ls_data["os_crypt"]:
        del ls_data["os_crypt"]["portal"]
        changed = True
    if "encrypted_key" in ls_data["os_crypt"]:
        del ls_data["os_crypt"]["encrypted_key"]
        changed = True

    if not changed:
        return

    # Write atomically
    tmp_path = ls_path.with_name(ls_path.name + ".tmp")
    try:
        tmp_path.write_text(json.dumps(ls_data, indent=2), "utf-8")
        tmp_path.rename(ls_path)
    except OSError as exc:
        print(
            f"Warning: Failed to write Local State — {exc}",
            file=sys.stderr,
        )


def encrypt_cookie_value(plaintext: str, key32: bytes) -> bytes:
    """Encrypt a cookie value using OSCrypt v11 (AES-128-CBC, static IV, PKCS7).

    Format::

        v11 (3 bytes) + AES-128-CBC ciphertext (variable)

    Uses PBKDF2-HMAC-SHA1 (1 iteration, salt=b"saltysalt") to derive a 16-byte
    AES-128 key from the 32-byte seed key, then encrypts with AES-128-CBC using
    a static IV of 16 ASCII spaces and PKCS7 padding.

    Args:
        plaintext: The cookie value to encrypt.
        key32: The 32-byte seed key from Local State's ``encrypted_key``.

    Returns:
        The v11-encrypted blob ready for ``encrypted_value``.
    """
    # Derive 16-byte AES-128 key via PBKDF2
    kdf = PBKDF2HMAC(
        algorithm=hashes.SHA1(),
        length=16,
        salt=b"saltysalt",
        iterations=1,
    )
    key16 = kdf.derive(key32)

    # AES-128-CBC with static IV + PKCS7 padding
    iv = b" " * 16
    cipher = Cipher(algorithms.AES(key16), modes.CBC(iv))
    encryptor = cipher.encryptor()
    padder = padding.PKCS7(128).padder()
    padded = padder.update(plaintext.encode("utf-8")) + padder.finalize()
    ciphertext = encryptor.update(padded) + encryptor.finalize()

    return b"v11" + ciphertext


# ── Cookie transformation ────────────────────────────────────────────────────


def transform_cookie(cookie: dict, enc_key: bytes) -> tuple:
    """Transform a Firefox cookie dict into a Vivaldi cookies row tuple.

    Args:
        cookie: Decoded Firefox cookie dict with fields:
            host, name, value, path, expiry, creationTime,
            isSecure, isHttpOnly, sameSite.
        enc_key: The 32-byte OSCrypt seed key for value encryption.

    Returns:
        A 20-element tuple matching ``INSERT_COOKIE_SQL`` parameters.
    """
    host_key = cookie.get("host", "")  # Keep leading dot for domain cookies
    name = cookie.get("name", "")
    value = cookie.get("value", "")
    path = cookie.get("path", "/")

    expiry = cookie.get("expiry", 0)
    creation_time_us = cookie.get("creationTime", 0)

    # expiry: Firefox stores MILLISECONDS since Unix epoch
    # → WebKit microseconds (add WebKit/Unix offset in µs)
    expires_utc = int(expiry * 1000 + 11644473600000000)

    # creationTime: Firefox stores MICROSECONDS (PRTime) since Unix epoch
    # → WebKit microseconds (add offset directly, no division needed)
    creation_utc = int(creation_time_us + 11644473600000000)

    is_secure = int(cookie.get("isSecure", 0))
    is_httponly = int(cookie.get("isHttpOnly", 0))
    firefox_samesite = int(cookie.get("sameSite", 0))

    samesite = _map_samesite(firefox_samesite, is_secure)
    has_expires = 1 if expiry > 0 else 0

    # Encrypt the cookie value using OSCrypt v11 (AES-128-CBC, PBKDF2)
    encrypted_value = encrypt_cookie_value(value, enc_key)

    # Column order matches INSERT_COOKIE_SQL.
    # Note: Chromium stores both value (plaintext, backwards compat) and
    #       encrypted_value (v11 ciphertext, authoritative).
    return (
        creation_utc,
        host_key,
        "",  # top_frame_site_key (no CHIPS support needed)
        name,
        value,  # plaintext (fallback for older Chromium versions)
        encrypted_value,  # OSCrypt v11 AES-128-CBC blob
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
    OSCrypt v11 (AES-128-CBC, PBKDF2), inserts all cookies, verifies
    integrity, then atomically renames to ``Cookies``.

    Args:
        cookies: List of decrypted cookie dicts.
        enc_key: 32-byte OSCrypt seed key.

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


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Write decrypted cookies to a Vivaldi Cookies database with "
            "OSCrypt v11 encryption (AES-128-CBC, PBKDF2). "
            "Reads a JSON array from stdin."
        ),
    )
    parser.add_argument(
        "--profile",
        required=True,
        help="Path to a Vivaldi profile directory (e.g. ~/.config/vivaldi/Default/)",
    )
    parser.add_argument(
        "--local-state",
        help=(
            "Path to Vivaldi's Local State JSON file "
            "(defaults to <profile_dir>/../Local State)"
        ),
    )
    args = parser.parse_args()

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

    # Resolve Local State path
    if args.local_state:
        local_state = str(Path(args.local_state).resolve())
    else:
        local_state = str(Path(args.profile).resolve().parent / "Local State")

    # Load or create the 32-byte OSCrypt seed key from gnome-keyring and
    # write it to Local State as v10 peanuts-wrapped.
    enc_key = _load_or_create_encryption_key(local_state)

    # Write cookies with OSCrypt v11 encryption
    count = write_cookies(cookies, args.profile, enc_key)

    profile_path = Path(args.profile).resolve()
    print(
        f"Wrote {count} cookies to {profile_path}/Cookies "
        f"(encrypted with v11 AES-128-CBC PBKDF2, key from gnome-keyring)"
    )


if __name__ == "__main__":
    main()
