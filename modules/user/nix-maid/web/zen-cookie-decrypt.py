#!/usr/bin/env python3
"""zen-cookie-decrypt: Decrypt encrypted cookies from Zen/Firefox using NSS SDR.

Reads JSON from stdin (output of zen-cookie-read.py), decrypts cookies
marked needs_decryption: true via NSS's PK11SDR_Decrypt, and outputs
decrypted JSON to stdout.

Usage:
    python3 zen-cookie-read.py --profile /path/to/profile \\
        | python3 zen-cookie-decrypt.py --profile /path/to/profile > decrypted.json
"""

import argparse
import ctypes
import ctypes.util
import json
import sys
from pathlib import Path


# ── NSS ctypes bindings ──────────────────────────────────────────────────────


class SECItem(ctypes.Structure):
    """NSS SECItem structure for passing data to/from NSS crypto functions."""

    _fields_: list[tuple[str, type]] = [
        ("type", ctypes.c_uint),
        ("data", ctypes.POINTER(ctypes.c_ubyte)),
        ("len", ctypes.c_uint),
    ]


def _load_nss() -> ctypes.CDLL:
    """Load libnss3.so and set up all function argument/return types."""
    lib_path = ctypes.util.find_library("nss3")
    if lib_path is None:
        print(
            "Error: libnss3.so not found. Install nss (Mozilla NSS) first.",
            file=sys.stderr,
        )
        sys.exit(1)

    nss: ctypes.CDLL = ctypes.CDLL(lib_path)

    # NSS_Init(char *configdir) -> SECStatus (0=SECSuccess, -1=SECFailure)
    nss.NSS_Init.argtypes = [ctypes.c_char_p]
    nss.NSS_Init.restype = ctypes.c_int

    # NSS_Shutdown() -> SECStatus
    nss.NSS_Shutdown.argtypes = []
    nss.NSS_Shutdown.restype = ctypes.c_int

    # PK11_GetInternalKeySlot() -> PK11SlotInfo*
    nss.PK11_GetInternalKeySlot.argtypes = []
    nss.PK11_GetInternalKeySlot.restype = ctypes.c_void_p

    # PK11_NeedLogin(PK11SlotInfo*) -> PRBool (0=false, non-zero=true)
    nss.PK11_NeedLogin.argtypes = [ctypes.c_void_p]
    nss.PK11_NeedLogin.restype = ctypes.c_int

    # PK11_CheckUserPassword(PK11SlotInfo*, char *pw) -> SECStatus
    # SECSuccess (0) means the password was accepted (including empty = no pw).
    nss.PK11_CheckUserPassword.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
    nss.PK11_CheckUserPassword.restype = ctypes.c_int

    # PK11_Authenticate(PK11SlotInfo*, PRBool loadCerts, void *wincx) -> SECStatus
    nss.PK11_Authenticate.argtypes = [
        ctypes.c_void_p,
        ctypes.c_int,
        ctypes.c_void_p,
    ]
    nss.PK11_Authenticate.restype = ctypes.c_int

    # PK11SDR_Decrypt(SECItem *data, SECItem *result, void *cx) -> SECStatus
    nss.PK11SDR_Decrypt.argtypes = [
        ctypes.POINTER(SECItem),
        ctypes.POINTER(SECItem),
        ctypes.c_void_p,
    ]
    nss.PK11SDR_Decrypt.restype = ctypes.c_int

    # SECITEM_FreeItem(SECItem *item, PRBool freeit) -> void
    nss.SECITEM_FreeItem.argtypes = [ctypes.POINTER(SECItem), ctypes.c_int]
    nss.SECITEM_FreeItem.restype = None

    return nss


def _check_profile(profile_dir: str) -> None:
    """Validate that the profile directory contains a usable NSS key database.

    Supports both modern (key4.db + cert9.db) and legacy
    (key3.db + cert8.db) NSS DB formats. Exits with code 1 if
    neither is present.
    """
    profile = Path(profile_dir)
    if not profile.is_dir():
        print(
            f"Error: profile directory not found: {profile_dir}",
            file=sys.stderr,
        )
        sys.exit(1)

    has_key4 = (profile / "key4.db").is_file()
    has_key3 = (profile / "key3.db").is_file()

    if not has_key4 and not has_key3:
        print(
            f"Error: NSS key database not found in {profile_dir}",
            file=sys.stderr,
        )
        sys.exit(1)


def _decrypt_one(nss: ctypes.CDLL, encrypted_hex: str) -> str:
    """Decrypt a single NSS-SDR-encrypted cookie value.

    Args:
        nss: Loaded libnss3 CDLL instance (NSS_Init must have been called).
        encrypted_hex: Hex-encoded NSS SDR-encrypted blob.

    Returns:
        Decrypted UTF-8 string.

    Raises:
        ValueError: If the hex string is malformed.
        RuntimeError: If NSS decryption fails.
    """
    encrypted_bytes = bytes.fromhex(encrypted_hex)
    data_len = len(encrypted_bytes)
    data_arr = (ctypes.c_ubyte * data_len)(*encrypted_bytes)

    input_item = SECItem(0, data_arr, data_len)
    output_item = SECItem(0, None, 0)

    status = nss.PK11SDR_Decrypt(
        ctypes.byref(input_item),
        ctypes.byref(output_item),
        None,
    )
    if status != 0:
        raise RuntimeError(f"PK11SDR_Decrypt returned status {status}")

    # Extract decrypted bytes from the output SECItem
    if output_item.data and output_item.len > 0:
        ptr = output_item.data
        decrypted = bytes(ptr[i] for i in range(output_item.len))
    else:
        decrypted = b""

    # Free the output SECItem buffer (allocated by NSS)
    if output_item.data:
        nss.SECITEM_FreeItem(ctypes.byref(output_item), 1)

    return decrypted.decode("utf-8", errors="replace")


def decrypt_cookies(cookies: list[dict], profile_dir: str) -> list[dict]:
    """Decrypt all cookies in the list that have ``needs_decryption: true``.

    Uses NSS SDR (Secret Decoder Ring) via the system's libnss3.so.
    Only cookies where ``needs_decryption`` is truthy are touched;
    all others pass through unchanged.
    """
    nss = _load_nss()

    # NSS_Init must be called once per profile before any crypto ops.
    # The argument is the profile directory (containing key4.db + cert9.db).
    rc = nss.NSS_Init(profile_dir.encode("utf-8"))
    if rc != 0:
        print(
            f"Error: NSS_Init failed for profile: {profile_dir}",
            file=sys.stderr,
        )
        sys.exit(1)

    try:
        slot = nss.PK11_GetInternalKeySlot()
        if not slot:
            print(
                "Error: PK11_GetInternalKeySlot returned NULL", file=sys.stderr
            )
            sys.exit(1)

        # Check whether the token needs authentication.
        # After fresh NSS_Init the token is *not* yet authenticated,
        # so PK11_NeedLogin returns true even when no master password
        # is set.  Distinguish the two cases by trying an empty password.
        if nss.PK11_NeedLogin(slot):
            pw_ok = nss.PK11_CheckUserPassword(slot, b"")
            if pw_ok != 0:
                print(
                    "Error: NSS master password is set. Cannot decrypt cookies "
                    "non-interactively. Disable master password in Zen first.",
                    file=sys.stderr,
                )
                sys.exit(2)
            # Empty password accepted -> token is now authenticated.

        # Explicit authenticate in case PK11_CheckUserPassword wasn't called.
        # This is effectively a no-op when already authenticated.
        if nss.PK11_Authenticate(slot, 0, None) != 0:
            print("Error: PK11_Authenticate failed", file=sys.stderr)
            sys.exit(1)

        # Decrypt each cookie that needs it
        for cookie in cookies:
            if cookie.get("needs_decryption"):
                encrypted_hex = cookie.get("encryptedValue", "")
                if encrypted_hex:
                    try:
                        plaintext = _decrypt_one(nss, encrypted_hex)
                        cookie["value"] = plaintext
                    except (ValueError, RuntimeError, OSError) as exc:
                        print(
                            f"Error: failed to decrypt cookie "
                            f"'{cookie.get('name', '?')}' on "
                            f"'{cookie.get('host', '?')}': {exc}",
                            file=sys.stderr,
                        )
                        cookie["value"] = ""
                else:
                    cookie["value"] = ""

                cookie["needs_decryption"] = False
                cookie.pop("encryptedValue", None)

    finally:
        nss.NSS_Shutdown()

    return cookies


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Decrypt encrypted cookies from Zen/Firefox using NSS SDR. "
            "Reads a JSON array from stdin (output of zen-cookie-read.py) "
            "and writes a decrypted JSON array to stdout."
        ),
    )
    parser.add_argument(
        "--profile",
        required=True,
        help="Path to a Zen/Firefox profile directory containing key4.db and cert9.db",
    )
    args = parser.parse_args()

    # Validate profile structure *before* consuming stdin
    _check_profile(args.profile)

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

    decrypted = decrypt_cookies(cookies, args.profile)
    json.dump(decrypted, sys.stdout, indent=2, ensure_ascii=False)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
