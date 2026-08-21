#!/usr/bin/env python3
"""Decrypt encrypted note fields inside an .apkg deck package.

Some commercially sold Anki decks encrypt parts of their note fields. The
encrypted segments are wrapped in `≯#...#≮` markers and hold base64 AES-CBC
(Pkcs7) ciphertext, decrypted at display time by obfuscated JS bundled in the
notetype. This tool rewrites the package so the fields contain plaintext:
the app can then import the deck like any other .apkg (no JS needed).

The key/iv are deck-specific and must be extracted manually from the deck's
own JS (e.g. by debugging on ankiweb). Known decks are bundled in
`KNOWN_DECKS`; anything else can be supplied via --key/--iv.

Only the legacy `collection.anki2` / `collection.anki21` storage formats are
supported. Decks exported from recent Anki versions may use the zstd-based
`collection.anki21b`; re-export those from Anki with "support older Anki
versions" enabled first.

Examples:
    python tool/anki_decrypt_apkg.py in.apkg -o out.apkg --deck math
    python tool/anki_decrypt_apkg.py in.apkg -o out.apkg --key KEY --iv IV
    python tool/anki_decrypt_apkg.py --selftest
"""

from __future__ import annotations

import argparse
import base64
import binascii
import re
import sqlite3
import sys
import tempfile
import zipfile
from pathlib import Path

MARKER_RE = re.compile(r"≯#(.*?)#≮")

# Deck-specific secrets recovered from each deck's own bundled JS, as
# documented in the anki-decryptBack reference repo. The IV below is the one
# both known decks ship with.
KNOWN_DECKS = {
    "hongbaoshu": {  # 红宝书
        "key": "XksZEmuDKw64afMJS5h2ckdUkxZuEyzi",
        "iv": "12345679abcdefgj",
    },
    "math": {  # 数学公式
        "key": "RmTysFEZ595bPsB5in6PRbgkSpmuWNBe",
        "iv": "12345679abcdefgj",
    },
}

# Known plaintext pair from anki-decryptBack/JavaScript/test.txt, used by
# --selftest to verify the AES backend before touching a real deck.
SELFTEST_CIPHER = "Y2R7XIluIcs5n5wOQZhruNSZt7w7jmgcKaIY/gWOJCM="
SELFTEST_PLAIN = "这个不用背，了解即可"
SELFTEST_DECK = "math"

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


def run_selftest() -> bool:
    deck = KNOWN_DECKS[SELFTEST_DECK]
    try:
        plain = decrypt_segment(
            SELFTEST_CIPHER, deck["key"].encode(), deck["iv"].encode()
        )
    except Exception as exc:  # noqa: BLE001 - selftest reports any failure
        print(f"selftest FAILED: {exc}", file=sys.stderr)
        return False
    if plain != SELFTEST_PLAIN:
        print(
            f"selftest FAILED: expected {SELFTEST_PLAIN!r}, got {plain!r}",
            file=sys.stderr,
        )
        return False
    print("selftest OK")
    return True


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Decrypt ≯#...#≮ segments in .apkg note fields."
    )
    parser.add_argument("input", nargs="?", type=Path, help="input .apkg")
    parser.add_argument("-o", "--output", type=Path, help="output .apkg")
    parser.add_argument(
        "--deck",
        choices=sorted(KNOWN_DECKS),
        help="use the bundled key/iv of a known deck",
    )
    parser.add_argument("--key", help="deck-specific AES key (UTF-8)")
    parser.add_argument("--iv", help="deck-specific AES iv (UTF-8)")
    parser.add_argument(
        "--selftest",
        action="store_true",
        help="verify the AES backend against a known pair and exit",
    )
    args = parser.parse_args()

    if args.selftest:
        return 0 if run_selftest() else 1

    if args.input is None or args.output is None:
        parser.error("input and -o/--output are required (or use --selftest)")

    if args.deck:
        key = KNOWN_DECKS[args.deck]["key"].encode()
        iv = KNOWN_DECKS[args.deck]["iv"].encode()
    elif args.key and args.iv:
        key = args.key.encode()
        iv = args.iv.encode()
    else:
        parser.error("provide --deck or both --key and --iv")

    if len(key) not in (16, 24, 32):
        parser.error(f"key must be 16/24/32 bytes, got {len(key)}")
    if len(iv) != 16:
        parser.error(f"iv must be 16 bytes, got {len(iv)}")

    if not run_selftest():
        print("error: AES backend broken, aborting", file=sys.stderr)
        return 1

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

        stats = decrypt_collection(tmp_collection, key, iv)
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
