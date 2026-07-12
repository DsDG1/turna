#!/usr/bin/env python3
"""Batch mix A1 listening lesson audio assets.

Combines fixed show intros/outros with generated main content and a
show-specific background music track that plays underneath the main content
only (not under intro/outro).

Output naming convention: S1U1L01A_mixed.mp3, S1U1L02B_mixed.mp3, ...

Requires:
  pip install pydub

Usage:
  python tool/mix_listening_a1.py all \
      --main-dir assets/sounds/turkish/listening/raw_a1 \
      --debut-dir assets/sounds/turkish/listening/debut \
      --fin-dir assets/sounds/turkish/listening/fin \
      --bgm-dir assets/sounds/turkish/listening/bgm \
      --mapping tool/mappings/a1_show_mapping.csv \
      --output-dir assets/sounds/turkish/listening/mixed_a1

The mapping CSV maps a main filename (without extension) to a show variant:
  S1U1L01,A
  S1U1L02,B
  S1U1L03,C
If a main file is not in the mapping, the default variant (A) is used.
"""

from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path
from typing import Dict, List


def require_pydub() -> None:
    """Fail early with a helpful message if pydub is not installed."""
    try:
        import pydub  # noqa: F401
    except ImportError as exc:
        print(
            "Error: pydub is required. Install it with:\n"
            "  pip install pydub\n"
            "ffmpeg must also be on PATH (pydub uses it for MP3 encoding).",
            file=sys.stderr,
        )
        raise SystemExit(1) from exc


from pydub import AudioSegment


DEFAULT_VARIANT = "A"
SUPPORTED_VARIANTS = {"A", "B", "C"}
BGM_GAIN_DB = -18.0  # Background music is much quieter than speech
MAIN_NORMALIZATION_DB = -3.0  # Prevent clipping after mixing
FADE_OUT_MS = 800  # Gentle fade out at the end of the BGM/main mix


def load_show_mapping(mapping_path: Path | None) -> Dict[str, str]:
    """Load lesson_id -> variant mapping from CSV."""
    mapping: Dict[str, str] = {}
    if mapping_path is None or not mapping_path.exists():
        return mapping

    with mapping_path.open("r", encoding="utf-8", newline="") as f:
        reader = csv.reader(f)
        for row in reader:
            if not row or row[0].startswith("#"):
                continue
            if len(row) < 2:
                continue
            lesson_id = row[0].strip()
            variant = row[1].strip().upper()
            if variant not in SUPPORTED_VARIANTS:
                print(
                    f"Warning: unknown variant '{variant}' for '{lesson_id}', "
                    f"using '{DEFAULT_VARIANT}'",
                    file=sys.stderr,
                )
                variant = DEFAULT_VARIANT
            mapping[lesson_id] = variant
    return mapping


def loop_bgm_to_length(bgm: AudioSegment, target_ms: int) -> AudioSegment:
    """Loop background music so it covers target_ms duration."""
    if len(bgm) >= target_ms:
        return bgm[:target_ms]

    repeats = (target_ms // len(bgm)) + 1
    extended = bgm * repeats
    return extended[:target_ms]


def mix_main_with_bgm(
    main: AudioSegment,
    bgm: AudioSegment,
    bgm_gain_db: float = BGM_GAIN_DB,
    fade_out_ms: int = FADE_OUT_MS,
) -> AudioSegment:
    """Overlay BGM onto main content at reduced volume."""
    target_ms = len(main)
    bgm_looped = loop_bgm_to_length(bgm, target_ms)

    # Lower BGM volume and add a gentle fade-out at the very end
    bgm_adjusted = bgm_looped + bgm_gain_db
    if len(bgm_adjusted) > fade_out_ms:
        bgm_adjusted = bgm_adjusted.fade_out(fade_out_ms)

    # Normalize main to leave headroom for the mix
    main_normalized = main.apply_gain(MAIN_NORMALIZATION_DB)

    return main_normalized.overlay(bgm_adjusted)


def build_lesson_audio(
    main_path: Path,
    debut_path: Path,
    fin_path: Path,
    bgm: AudioSegment,
    output_path: Path,
) -> None:
    """Compose one final listening lesson MP3."""
    main = AudioSegment.from_mp3(main_path)
    debut = AudioSegment.from_mp3(debut_path)
    fin = AudioSegment.from_mp3(fin_path)

    mixed_main = mix_main_with_bgm(main, bgm)

    final = debut + mixed_main + fin

    output_path.parent.mkdir(parents=True, exist_ok=True)
    final.export(output_path, format="mp3", parameters=["-q:a", "4"])


def collect_main_files(main_dir: Path) -> List[Path]:
    """Return all .mp3 files in main_dir, sorted."""
    if not main_dir.exists():
        raise FileNotFoundError(f"Main directory not found: {main_dir}")
    files = sorted(main_dir.glob("*.mp3"))
    return files


def resolve_variant_file(
    variant: str,
    base_name: str,
    directory: Path,
    suffix: str,
) -> Path:
    """Resolve e.g. debutA.mp3 or finA.mp3 path."""
    candidate = directory / f"{base_name}{variant}.mp3"
    if candidate.exists():
        return candidate

    # Fallback: try lowercase variant if uppercase file not found
    candidate_lower = directory / f"{base_name}{variant.lower()}.mp3"
    if candidate_lower.exists():
        return candidate_lower

    raise FileNotFoundError(
        f"Missing {suffix} file for variant '{variant}': "
        f"expected {candidate} (or lowercase variant)"
    )


def cmd_all(args: argparse.Namespace) -> int:
    """Batch process all main files."""
    mapping = load_show_mapping(args.mapping)

    # Pre-load all three BGM variants so we don't re-read them per file.
    bgm_variants: Dict[str, AudioSegment] = {}
    for variant in SUPPORTED_VARIANTS:
        bgm_path = resolve_variant_file(variant, "bgm", args.bgm_dir, "bgm")
        bgm_variants[variant] = AudioSegment.from_mp3(bgm_path)

    main_files = collect_main_files(args.main_dir)
    if not main_files:
        print(f"No .mp3 files found in {args.main_dir}", file=sys.stderr)
        return 1

    processed = 0
    skipped = 0
    errors: List[str] = []

    for main_path in main_files:
        lesson_id = main_path.stem  # e.g. S1U1L01A
        variant = mapping.get(lesson_id, args.default_variant).upper()

        output_name = f"{lesson_id}_mixed.mp3"
        output_path = args.output_dir / output_name

        if output_path.exists() and not args.force:
            skipped += 1
            print(f"Skipped (exists): {output_name}")
            continue

        try:
            debut_path = resolve_variant_file(variant, "debut", args.debut_dir, "debut")
            fin_path = resolve_variant_file(variant, "fin", args.fin_dir, "fin")
            bgm = bgm_variants[variant]

            build_lesson_audio(
                main_path=main_path,
                debut_path=debut_path,
                fin_path=fin_path,
                bgm=bgm,
                output_path=output_path,
            )
            processed += 1
            print(f"Generated: {output_name} (variant {variant})")
        except Exception as exc:
            errors.append(f"{lesson_id}: {exc}")
            print(f"Error: {lesson_id}: {exc}", file=sys.stderr)

    print(
        f"\nDone: {processed} generated, {skipped} skipped, "
        f"{len(errors)} errors, {len(main_files)} total."
    )
    return 0 if not errors else 1


def cmd_one(args: argparse.Namespace) -> int:
    """Process a single main file."""
    variant = args.variant.upper()
    bgm_path = resolve_variant_file(variant, "bgm", args.bgm_dir, "bgm")
    bgm = AudioSegment.from_mp3(bgm_path)

    output_path = args.output or args.output_dir / f"{args.main_path.stem}_mixed.mp3"
    output_path.parent.mkdir(parents=True, exist_ok=True)

    debut_path = resolve_variant_file(variant, "debut", args.debut_dir, "debut")
    fin_path = resolve_variant_file(variant, "fin", args.fin_dir, "fin")

    build_lesson_audio(
        main_path=args.main_path,
        debut_path=debut_path,
        fin_path=fin_path,
        bgm=bgm,
        output_path=output_path,
    )
    print(f"Generated: {output_path}")
    return 0


def main(argv: list[str] | None = None) -> int:
    require_pydub()

    parser = argparse.ArgumentParser(
        description="Batch mix A1 listening lesson audio"
    )
    parser.add_argument(
        "--main-dir",
        type=Path,
        default=Path("assets/sounds/turkish/listening/raw_a1"),
        help="Directory containing generated main content MP3s",
    )
    parser.add_argument(
        "--debut-dir",
        type=Path,
        default=Path("assets/sounds/turkish/listening/debut"),
        help="Directory containing debutA.mp3, debutB.mp3, debutC.mp3",
    )
    parser.add_argument(
        "--fin-dir",
        type=Path,
        default=Path("assets/sounds/turkish/listening/fin"),
        help="Directory containing finA.mp3, finB.mp3, finC.mp3",
    )
    parser.add_argument(
        "--bgm-dir",
        type=Path,
        default=Path("assets/sounds/turkish/listening/bgm"),
        help="Directory containing bgmA.mp3, bgmB.mp3, bgmC.mp3",
    )
    parser.add_argument(
        "--mapping",
        type=Path,
        default=None,
        help="CSV mapping main filename -> variant (A/B/C)",
    )
    parser.add_argument(
        "--default-variant",
        choices=["A", "B", "C"],
        default="A",
        help="Variant to use when not in mapping",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("assets/sounds/turkish/listening/mixed_a1"),
        help="Output directory for mixed MP3s",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Regenerate files even if they already exist",
    )

    subparsers = parser.add_subparsers(dest="command", required=True)

    p_all = subparsers.add_parser(
        "all", help="Batch process all main files in --main-dir"
    )
    p_all.set_defaults(func=cmd_all)

    p_one = subparsers.add_parser(
        "one", help="Process a single main file"
    )
    p_one.add_argument("main_path", type=Path, help="Path to main MP3 file")
    p_one.add_argument(
        "--variant",
        choices=["A", "B", "C"],
        default="A",
        help="Show variant for this file",
    )
    p_one.add_argument(
        "--output",
        type=Path,
        default=None,
        help="Override output file path",
    )
    p_one.set_defaults(func=cmd_one)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
