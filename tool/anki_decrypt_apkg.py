#!/usr/bin/env python3
"""Decrypt encrypted note fields inside an .apkg deck package.

Some commercially sold Anki decks encrypt parts of their note fields. The
encrypted segments are wrapped in `≯#...#≮` markers and hold base64 AES-CBC
(Pkcs7) ciphertext, decrypted at display time by obfuscated JS bundled in the
notetype. This tool rewrites the package so the fields contain plaintext:
the app can then import the deck like any other .apkg (no JS needed).

The key/iv are deck-specific and must be extracted manually from the deck's
own JS (e.g. by debugging on ankiweb). Supply them via --key/--iv or the
TURNA_ANKI_DECRYPT_KEY / TURNA_ANKI_DECRYPT_IV environment variables —
deck secrets are deliberately NOT bundled in this repository (known-deck
keys shipped here previously and were removed for IP/liability reasons).

Only the legacy `collection.anki2` / `collection.anki21` storage formats are
supported. Decks exported from recent Anki versions may use the zstd-based
`collection.anki21b`; re-export those from Anki with "support older Anki
versions" enabled first.

Example:
    python tool/anki_decrypt_apkg.py in.apkg -o out.apkg --key KEY --iv IV
"""

from __future__ import annotations

import argparse
import base64
import binascii
import os
import re
import sqlite3
import sys
import tempfile
import zipfile
from pathlib import Path

MARKER_RE = re.compile(r"≯#(.*?)#≮")

COLLECTION_NAMES = ("collection.anki21", "collection.anki2")


def _aes_decrypt_cbc(ciphertext: bytes, key: bytes, iv: bytes) -> bytes:
    """Decrypt AES-CBC and strip PKCS7 padding.

    Prefers pycryptodome, falls back to the `cryptography` package; at least
    one must be installed.
    """
    try:
        from Crypto.Cipher import AES  # pycryptodome

        return AES.new(key, AES.MODE_CBC, iv).decrypt(ciphertext)
    except ImportError:
        pass
    try:
        from cryptography.hazmat.primitives.ciphers import (
            Cipher,
            algorithms,
            modes,
        )

        decryptor = Cipher(algorithms.AES(key), modes.CBC(iv)).decryptor()
        return decryptor.update(ciphertext) + decryptor.finalize()
    except ImportError:
        pass
    print(
        "error: no AES backend available; install pycryptodome or cryptography",
        file=sys.stderr,
    )
    sys.exit(1)


def decrypt_segment(b64_ciphertext: str, key: bytes, iv: bytes) -> str:
    raw = base64.b64decode(b64_ciphertext)
    padded = _aes_decrypt_cbc(raw, key, iv)
    pad_len = padded[-1]
    if pad_len < 1 or pad_len > 16:
        raise ValueError("invalid PKCS7 padding (wrong key/iv?)")
    return padded[:-pad_len].decode("utf-8")


def decrypt_text(text: str, key: bytes, iv: bytes) -> tuple[str, int, int]:
    """Replace every marked segment in `text`. Returns (text, ok, failed)."""
    ok = 0
    failed = 0

    def repl(match: re.Match[str]) -> str:
        nonlocal ok, failed
        try:
            plain = decrypt_segment(match.group(1), key, iv)
        except (ValueError, binascii.Error, UnicodeDecodeError):
            failed += 1
            return match.group(0)  # leave undecryptable segments untouched
        ok += 1
        return plain

    return MARKER_RE.sub(repl, text), ok, failed


def decrypt_collection(collection_path: Path, key: bytes, iv: bytes) -> dict:
    conn = sqlite3.connect(collection_path)
    try:
        rows = conn.execute("SELECT id, flds FROM notes").fetchall()
        notes_changed = 0
        segments_ok = 0
        segments_failed = 0
        for note_id, flds in rows:
            if "≯#" not in flds:
                continue
            new_flds, ok, failed = decrypt_text(flds, key, iv)
            segments_ok += ok
            segments_failed += failed
            if new_flds != flds:
                conn.execute(
                    "UPDATE notes SET flds = ? WHERE id = ?", (new_flds, note_id)
                )
                notes_changed += 1
        conn.commit()
        return {
            "notes_scanned": len(rows),
            "notes_changed": notes_changed,
            "segments_decrypted": segments_ok,
            "segments_failed": segments_failed,
        }
    finally:
        conn.close()


def repack_with_collection(
    src_apkg: Path, dst_apkg: Path, collection_name: str, collection_path: Path
) -> None:
    with zipfile.ZipFile(src_apkg) as zin, zipfile.ZipFile(
        dst_apkg, "w", zipfile.ZIP_DEFLATED
    ) as zout:
        for item in zin.infolist():
            if item.filename == collection_name:
                zout.writestr(item, collection_path.read_bytes())
            else:
                zout.writestr(item, zin.read(item.filename))


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Decrypt ≯#...#≮ segments in .apkg note fields."
    )
    parser.add_argument("input", nargs="?", type=Path, help="input .apkg")
    parser.add_argument("-o", "--output", type=Path, help="output .apkg")
    parser.add_argument(
        "--key",
        help="deck-specific AES key (UTF-8), or TURNA_ANKI_DECRYPT_KEY",
    )
    parser.add_argument(
        "--iv",
        help="deck-specific AES iv (UTF-8), or TURNA_ANKI_DECRYPT_IV",
    )
    args = parser.parse_args()

    key = args.key or os.environ.get("TURNA_ANKI_DECRYPT_KEY")
    iv = args.iv or os.environ.get("TURNA_ANKI_DECRYPT_IV")

    if args.input is None or args.output is None:
        parser.error("input and -o/--output are required")
    if not key or not iv:
        parser.error(
            "provide both --key and --iv (or TURNA_ANKI_DECRYPT_KEY / "
            "TURNA_ANKI_DECRYPT_IV); known-deck keys are no longer bundled"
        )

    key_bytes = key.encode()
    iv_bytes = iv.encode()
    if len(key_bytes) not in (16, 24, 32):
        parser.error(f"key must be 16/24/32 bytes, got {len(key_bytes)}")
    if len(iv_bytes) != 16:
        parser.error(f"iv must be 16 bytes, got {len(iv_bytes)}")

    with zipfile.ZipFile(args.input) as zf:
        names = set(zf.namelist())
        if "collection.anki21b" in names:
            print(
                "error: deck uses collection.anki21b (zstd). Re-export from "
                "Anki with 'support older Anki versions' enabled.",
                file=sys.stderr,
            )
            return 1
        collection_name = next(
            (n for n in COLLECTION_NAMES if n in names), None
        )
        if collection_name is None:
            print(
                "error: no collection.anki2/anki21 found in package",
                file=sys.stderr,
            )
            return 1

    with tempfile.TemporaryDirectory() as tmp:
        tmp_collection = Path(tmp) / collection_name
        with zipfile.ZipFile(args.input) as zf:
            tmp_collection.write_bytes(zf.read(collection_name))

        stats = decrypt_collection(tmp_collection, key_bytes, iv_bytes)
        repack_with_collection(
            args.input, args.output, collection_name, tmp_collection
        )

    print(
        "done: {notes_changed}/{notes_scanned} notes updated, "
        "{segments_decrypted} segments decrypted, "
        "{segments_failed} failed (left as-is) -> {out}".format(
            out=args.output, **stats
        )
    )
    return 0 if stats["segments_failed"] == 0 else 2


if __name__ == "__main__":
    sys.exit(main())
