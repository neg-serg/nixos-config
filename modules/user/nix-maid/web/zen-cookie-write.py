#!/usr/bin/env python3
# allow: SIZE_OK — single-file Nix script (writeTextFile); encryption, schema,
#        and DB write are an indivisible pipeline; splitting would require a
#        separate Python package beyond scope.

"""zen-cookie-write: Write decrypted cookies to a Vivaldi Cookies SQLite database
with OSCrypt v11 encryption (AES-128-CBC).

Reads decrypted JSON from stdin (output of zen-cookie-decrypt.py), transforms
Firefox cookie fields to Vivaldi 8.0 (Chromium ~130) schema, encrypts values
with OSCrypt v11 (AES-128-CBC, PBKDF2 key derivation), and writes atomically
to the target Cookies database.

The encryption key is derived from a secret in gnome-keyring (Chrome Safe
Storage) via PBKDF2-HMAC-SHA1; no Local State file is consulted or updated.

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
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
from cryptography.hazmat.primitives import hashes, padding


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


# ── OSCrypt v11 encryption helpers ───────────────────────────────────────────

# Chromium OSCrypt v11 uses deliberately weak PBKDF2 parameters for fast
# startup: 1 iteration, SHA1, fixed salt "saltysalt", 16-byte AES-128 key.
_SALT = b"saltysalt"
_ITERATIONS = 1
_KEY_LENGTH = 16  # AES-128
_PBKDF2_HASH = hashes.SHA1()


def _derive_key_from_secret(secret: bytes) -> bytes:
    """Derive a 16-byte AES-128 key from the keyring secret using PBKDF2.

    Chromium OSCrypt v11:
        PBKDF2-HMAC-SHA1(secret, salt=b"saltysalt", iterations=1, length=16)

    Args:
        secret: The raw secret bytes from gnome-keyring (any length).

    Returns:
        16-byte AES-128-CBC key.
    """
    kdf = PBKDF2HMAC(
        algorithm=_PBKDF2_HASH,
        length=_KEY_LENGTH,
        salt=_SALT,
        iterations=_ITERATIONS,
    )
    return kdf.derive(secret)


# ── Gnome-keyring helpers ──────────────────────────────────────────────────

# Attribute sets to try when looking up the key in gnome-keyring, in order
# of specificity. Vivaldi 8.0 stores the key under "Chrome Safe Storage"
# with ``application=vivaldi`` and one of several possible schema attributes.
_KEYRING_ATTR_SETS: list[list[str]] = [
    ["application", "vivaldi", "xdg:schema", "org.chromium.Chromium"],
    ["application", "vivaldi", "xdg:schema", "chrome_libsecret_os_crypt_password_v2"],
    ["application", "vivaldi"],
    ["xdg:schema", "org.chromium.Chromium"],
    ["xdg:schema", "chrome_libsecret_os_crypt_password_v2"],
]


def _get_secret_from_keyring() -> bytes | None:
    """Read the raw OSCrypt v11 secret from gnome-keyring.

    Vivaldi 8.0 / Chromium stores the OSCrypt v11 encryption seed in
    gnome-keyring under the ``Chrome Safe Storage`` label.  The PBKDF2
    key is derived from this secret (any length — typically 32 random bytes).

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
    """Store a raw OSCrypt v11 secret in gnome-keyring.

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
                "secret-tool", "store",
                "--label", "Chrome Safe Storage",
                "application", "vivaldi",
                "xdg:schema", "org.chromium.Chromium",
            ],
            input=secret,
            capture_output=True,
            timeout=5,
        )
        return result.returncode == 0
    except (FileNotFoundError, subprocess.TimeoutExpired, OSError):
        return False


def _load_or_create_encryption_key() -> bytes:
    """Load or create the OSCrypt v11 encryption key via gnome-keyring + PBKDF2.

    Vivaldi 8.0 / Chromium 80+ stores a random seed in the OS keyring and
    derives the actual AES-128-CBC key via:
        PBKDF2-HMAC-SHA1(secret, salt=b"saltysalt", iterations=1, length=16)

    Resolution order:

    1. **Gnome-keyring** – Look up the secret under ``Chrome Safe Storage``.
       If found, derive the 16-byte key and return it.
    2. **Generate new** – Create a fresh 32-byte random secret, store it in
       gnome-keyring with the proper Vivaldi attributes, derive the key.

    Returns:
        The 16-byte AES-128-CBC key derived from the OSCrypt v11 secret.

    Raises:
        SystemExit: On keyring storage failure (exit code 5).
    """
    # ── Step 1: Gnome-keyring ───────────────────────────────────────────────
    secret = _get_secret_from_keyring()
    if secret is not None:
        return _derive_key_from_secret(secret)

    # ── Step 2: Generate new secret ──────────────────────────────────────────
    new_secret = os.urandom(32)
    if not _store_secret_in_keyring(new_secret):
        print(
            "Error: Failed to store new OSCrypt v11 secret in gnome-keyring",
            file=sys.stderr,
        )
        sys.exit(5)

    return _derive_key_from_secret(new_secret)


def _lock_portal(local_state_path: str) -> None:
    """Lock the portal in Vivaldi Local State to prevent key reset on startup.

    Vivaldi 8.0 always tries to (re-)create the portal on startup. If
    ``prev_init_success`` is missing or ``false``, Vivaldi overwrites
    ``encrypted_key`` with garbage, which destroys all our cookies.

    By setting ``prev_init_success: true`` in the ``portal`` section of
    ``os_crypt``, we signal that the portal already exists and is valid.
    Vivaldi skips the re-init, keeping our encryption key intact.

    Args:
        local_state_path: Path to Vivaldi's ``Local State`` JSON file.
    """
    ls_path = Path(local_state_path)
    if not ls_path.is_file():
        return

    try:
        ls = json.loads(ls_path.read_text())
    except (json.JSONDecodeError, OSError):
        return

    os_crypt: dict = ls.get("os_crypt", {})
    if "portal" not in os_crypt:
        os_crypt["portal"] = {
            "prev_desktop": "Hyprland",
            "prev_init_success": True,
        }
        ls["os_crypt"] = os_crypt
        try:
            ls_path.write_text(json.dumps(ls, indent=2))
        except OSError:
            pass


def encrypt_cookie_value(plaintext: str, key: bytes) -> bytes:
    """Encrypt a cookie value using OSCrypt v11 (AES-128-CBC, PKCS7 padding).

    Format::

        v11 (3 bytes) + ciphertext (variable, AES-128-CBC)

    Uses the Chromium-standard static IV of 16 ASCII spaces and PKCS7
    padding.  The key is the 16-byte AES-128 key derived from the
    keyring secret via PBKDF2.

    Args:
        plaintext: The cookie value to encrypt.
        key: The 16-byte AES-128-CBC key.

    Returns:
        The v11-encrypted blob ready for ``encrypted_value``.
    """
    iv = b" " * 16
    cipher = Cipher(algorithms.AES(key), modes.CBC(iv))
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
        enc_key: The 16-byte AES-128-CBC key for value encryption.

    Returns:
        A 20-element tuple matching ``INSERT_COOKIE_SQL`` parameters.
    """
    host_key = cookie.get("host", "")  # Keep leading dot for domain cookies
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

    # Encrypt the cookie value using OSCrypt v11
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
    OSCrypt v11 (AES-128-CBC), inserts all cookies, verifies integrity, then
    atomically renames to ``Cookies``.

    Args:
        cookies: List of decrypted cookie dicts.
        profile_dir: Path to Vivaldi profile directory.
        enc_key: 16-byte AES-128-CBC encryption key.

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
            "OSCrypt v11 encryption (AES-128-CBC, PBKDF2 key derivation). "
            "Reads a JSON array from stdin."
        ),
    )
    parser.add_argument(
        "--profile",
        required=True,
        help="Path to a Vivaldi profile directory (e.g. ~/.config/vivaldi/Default/)",
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

    # Load or derive the OSCrypt v11 encryption key from gnome-keyring
    enc_key = _load_or_create_encryption_key()

    # Lock the portal in Local State so Vivaldi does not regenerate the
    # encryption key on next startup (which would invalidate our cookies).
    local_state = str(Path(args.profile).resolve().parent / "Local State")
    _lock_portal(local_state)

    # Write cookies with OSCrypt v11 encryption
    count = write_cookies(cookies, args.profile, enc_key)

    profile_path = Path(args.profile).resolve()
    print(
        f"Wrote {count} cookies to {profile_path}/Cookies "
        f"(encrypted with v11, key derived from gnome-keyring via PBKDF2)"
    )


if __name__ == "__main__":
    main()
