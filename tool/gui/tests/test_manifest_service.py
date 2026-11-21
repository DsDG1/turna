"""Unit tests for Phase Two media_manifest.json and audio_manifest.json service."""
from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

_GUI = Path(__file__).resolve().parents[1]
if str(_GUI) not in sys.path:
    sys.path.insert(0, str(_GUI))

from src.backend.manifest_service import (
    audit_audio_manifest,
    audit_audio_manifest_doc,
    audit_media_manifest,
    build_media_gate,
    load_audio_manifest_doc,
    load_media_manifest,
    register_missing_media_entries,
    save_audio_manifest_doc,
    save_media_manifest,
)


class ManifestServiceTest(unittest.TestCase):
    def test_audit_and_register_missing_media(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            course = Path(tmp)
            (course / "media").mkdir()
            (course / "media" / "cay.svg").write_text("<svg/>", encoding="utf-8")
            (course / "media_manifest.json").write_text(
                json.dumps(
                    {
                        "version": 1,
                        "assets": [
                            {"asset": "media/ghost.svg", "kind": "image", "alt": "", "reviewStatus": "pending"}
                        ],
                    }
                ),
                encoding="utf-8",
            )
            adapter = SimpleNamespace(
                course_dir=course,
                sections=[
                    {
                        "id": "s1",
                        "units": [
                            {
                                "id": "u1",
                                "lessons": [
                                    {
                                        "id": "l1",
                                        "content": {
                                            "readingPassage": {
                                                "imageAsset": "media/cay.svg",
                                                "imageAlt": "红茶",
                                            }
                                        },
                                    }
                                ],
                            }
                        ],
                    }
                ],
                vocab=[],
                expressions=[],
            )
            summary = audit_media_manifest(adapter)
            self.assertEqual(summary.registered_count, 1)
            self.assertEqual(summary.missing_files, ("media/ghost.svg",))
            self.assertEqual(summary.unregistered_refs, ("media/cay.svg",))
            self.assertEqual(summary.unused_entries, ("media/ghost.svg",))
            self.assertEqual(summary.pending_review_count, 1)
            gate = build_media_gate(summary, audit_audio_manifest(adapter))
            self.assertEqual(
                {item["code"] for item in gate["blockers"]}, {"image_unregistered"}
            )

            doc = load_media_manifest(course)
            added = register_missing_media_entries(adapter, doc)
            self.assertEqual(added, 1)
            doc["assets"][-1]["reviewStatus"] = "rendered-locally"
            save_media_manifest(course, doc)

            summary2 = audit_media_manifest(adapter)
            self.assertEqual(summary2.unregistered_refs, ())
            self.assertEqual(summary2.registered_count, 2)
            gate2 = build_media_gate(summary2, audit_audio_manifest(adapter))
            self.assertEqual(
                {item["code"] for item in gate2["blockers"]}, {"image_review"}
            )

    def test_audio_manifest_doc_roundtrip_and_audit(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            course = Path(tmp)
            doc = load_audio_manifest_doc(course)
            doc["assets"].append(
                {
                    "asset": "nt-u1-listen-1-words",
                    "lessonId": "nt-u1-listen-1",
                    "speakers": ["Ayşe"],
                    "speed": 0.9,
                    "reviewStatus": "pending",
                    "text": "çay, kahve",
                }
            )
            doc["assets"].append(
                {
                    "asset": "nt-u1-listen-1-summary",
                    "lessonId": "nt-u1-listen-1",
                    "speakers": ["Ayşe"],
                    "speed": 0.9,
                    "reviewStatus": "approved",
                    "text": "总结",
                }
            )
            save_audio_manifest_doc(course, doc)
            summary = audit_audio_manifest_doc(course)
            self.assertEqual(summary["total"], 2)
            self.assertEqual(summary["pending_count"], 1)
            self.assertEqual(summary["approved_count"], 1)

    def test_audio_gate_uses_current_refs_and_ignores_unused_entries(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            course = repo / "assets" / "courses" / "nouveau-turkish"
            course.mkdir(parents=True)
            (course / "index.json").write_text(
                json.dumps({"language": "tr", "sections": []}), encoding="utf-8"
            )
            (course / "media").mkdir()
            (course / "media" / "cay.svg").write_text("<svg/>", encoding="utf-8")
            audio_path = (
                repo
                / "assets"
                / "sounds"
                / "turkish"
                / "listening"
                / "l-pilot.mp3"
            )
            audio_path.parent.mkdir(parents=True)
            audio_path.write_bytes(b"mp3")
            save_media_manifest(
                course,
                {
                    "assets": [
                        {
                            "asset": "media/cay.svg",
                            "reviewStatus": "existing-asset",
                        }
                    ]
                },
            )
            save_audio_manifest_doc(
                course,
                {
                    "status": "pending-generation-and-human-review",
                    "assets": [
                        {"asset": "l-pilot", "reviewStatus": "pending"},
                        {"asset": "stale", "reviewStatus": "pending"},
                    ],
                },
            )
            adapter = SimpleNamespace(
                course_dir=course,
                sections=[
                    {
                        "id": "s1",
                        "units": [
                            {
                                "id": "u1",
                                "lessons": [
                                    {
                                        "id": "l1",
                                        "content": {
                                            "readingPassage": {
                                                "imageAsset": "media/cay.svg"
                                            },
                                            "listeningPhases": [
                                                {
                                                    "audioAsset": "l-pilot",
                                                },
                                                {
                                                    "audioAsset": "w-cay",
                                                },
                                            ],
                                        },
                                    }
                                ],
                            }
                        ],
                    }
                ],
                vocab=[{"id": "w-cay"}],
                expressions=[],
            )

            media = audit_media_manifest(adapter)
            audio = audit_audio_manifest(adapter)
            self.assertEqual(audio.referenced_count, 1)
            self.assertEqual(audio.missing_files, ())
            self.assertEqual(audio.pending_review_refs, ("l-pilot",))
            self.assertEqual(audio.unused_entries, ("stale",))
            gate = build_media_gate(media, audio)
            self.assertEqual(
                {item["code"] for item in gate["blockers"]}, {"audio_review"}
            )

            doc = load_audio_manifest_doc(course)
            doc["assets"][0]["reviewStatus"] = "approved"
            save_audio_manifest_doc(course, doc)
            final_gate = build_media_gate(
                audit_media_manifest(adapter), audit_audio_manifest(adapter)
            )
            self.assertTrue(final_gate["ok"])
            self.assertEqual(final_gate["blockers"], [])

    def test_audio_gate_reports_missing_and_unregistered_current_ref(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            course = Path(tmp) / "course"
            course.mkdir()
            (course / "index.json").write_text(
                json.dumps({"language": "tr", "sections": []}), encoding="utf-8"
            )
            adapter = SimpleNamespace(
                course_dir=course,
                sections=[
                    {
                        "id": "s1",
                        "units": [
                            {
                                "id": "u1",
                                "lessons": [
                                    {
                                        "id": "l1",
                                        "content": {
                                            "listeningPhases": [
                                                {"audioAsset": "l-missing"}
                                            ]
                                        },
                                    }
                                ],
                            }
                        ],
                    }
                ],
                vocab=[],
                expressions=[],
            )
            gate = build_media_gate(
                audit_media_manifest(adapter), audit_audio_manifest(adapter)
            )
            self.assertFalse(gate["ok"])
            self.assertEqual(
                {item["code"] for item in gate["blockers"]},
                {"audio_missing", "audio_unregistered"},
            )


if __name__ == "__main__":
    unittest.main()
