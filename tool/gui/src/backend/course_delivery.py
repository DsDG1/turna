"""Hand a GUI course to the Flutter app.

Two doors, and they do not rewrite each other's ids:

* A course whose directory is ``assets/courses/<dir>/`` inside this checkout
  is registered in ``manifest.json`` and ``pubspec.yaml``. Lesson ids on disk
  stay as the author wrote them.
* Anything else (or an explicit output path) becomes a ``.turnapack``. Ids in
  the pack copy gain a stable ``ll-<code>-`` prefix. The editor's JSON is left
  alone.

The app importer requires a license object whose name and attribution are
non-empty. The course file may store an empty attribution; the pack envelope
fills that with the display name so the import can succeed.
"""
from __future__ import annotations

import json
import re
import zipfile
from copy import deepcopy
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from src.backend.course_media import ALLOWED_MEDIA_EXTENSIONS

CODE_RE = re.compile(r"^[a-z]{2,3}$")
ALWAYS_RESERVED_CODES = frozenset({"tr", "fr", "anki"})
DEFAULT_LICENSE_NAME = "All rights reserved"

REFERENCE_STRING_KEYS = frozenset({
    "wordId",
    "expressionId",
    "grammarPointId",
})
REFERENCE_LIST_KEYS = frozenset({
    "prerequisiteSectionIds",
    "prerequisiteUnitIds",
    "prerequisiteLessonIds",
    "linkedGrammarPointIds",
    "linkedWordIds",
    "linkedExpressionIds",
    "exampleExpressionIds",
    "exampleSentenceIds",
    "targetExpressionIds",
    "targetGrammarPointIds",
})
MEDIA_STRING_KEYS = frozenset({"audioAsset", "imageAsset"})
MEDIA_LIST_KEYS = frozenset({"audioAssets", "imageAssets"})

_REQUIRED_COURSE_FILES = ("index.json", "vocab.json")


class DeliveryError(Exception):
    """The course cannot be handed to the app."""


@dataclass(frozen=True)
class LanguageProfile:
    code: str
    display_name: str
    tts_locale: str
    native_label: str
    signature_chars: str
    license_name: str
    license_attribution: str
    license_link: str


@dataclass(frozen=True)
class HandoffResult:
    ok: bool
    message: str
    output_path: str = ""


def default_repo_root() -> Path:
    return Path(__file__).resolve().parents[4]


def _nonempty(*values: Any) -> str:
    for value in values:
        if value is None:
            continue
        text = str(value).strip()
        if text:
            return text
    return ""


def _default_tts(code: str) -> str:
    if len(code) == 2:
        return f"{code}-{code.upper()}"
    return code


def resolve_profile(
    index: dict[str, Any],
    *,
    manifest_entry: dict[str, Any] | None = None,
) -> LanguageProfile:
    """Descriptor fields from the index, then an existing manifest row, then defaults."""
    entry = manifest_entry or {}
    code = str(index.get("language") or "").strip()
    if not CODE_RE.fullmatch(code):
        raise DeliveryError(f"语言代码必须匹配 ^[a-z]{{2,3}}$（当前：{code!r}）")
    display = _nonempty(index.get("displayName"), entry.get("displayName"), code)
    license_raw = index.get("license")
    license = license_raw if isinstance(license_raw, dict) else {}
    return LanguageProfile(
        code=code,
        display_name=display,
        tts_locale=_nonempty(index.get("ttsLocale"), entry.get("ttsLocale"), _default_tts(code)),
        native_label=_nonempty(index.get("nativeLabel"), entry.get("nativeLabel"), display),
        signature_chars=_nonempty(index.get("signatureChars"), entry.get("signatureChars")),
        license_name=_nonempty(license.get("name"), DEFAULT_LICENSE_NAME),
        license_attribution=str(license.get("attribution") or "").strip(),
        license_link=str(license.get("link") or "").strip(),
    )


def apply_profile(index: dict[str, Any], profile: LanguageProfile) -> None:
    """Write descriptor fields onto the in-memory index. Does not change ``language``."""
    index["ttsLocale"] = profile.tts_locale
    index["nativeLabel"] = profile.native_label
    if profile.signature_chars:
        index["signatureChars"] = profile.signature_chars
    index["license"] = {
        "name": profile.license_name,
        "attribution": profile.license_attribution,
        "link": profile.license_link,
    }


def repo_course_dir_name(course_dir: Path, repo_root: Path) -> str | None:
    """Directory name when ``course_dir`` is exactly ``assets/courses/<dir>``."""
    courses = (Path(repo_root) / "assets" / "courses").resolve()
    try:
        rel = Path(course_dir).resolve().relative_to(courses)
    except ValueError:
        return None
    if len(rel.parts) != 1 or rel.parts[0] in {"", "."}:
        return None
    return rel.parts[0]


def builtin_codes(repo_root: Path) -> set[str]:
    """Manifest language codes plus ``tr`` / ``fr`` / ``anki``."""
    codes = set(ALWAYS_RESERVED_CODES)
    manifest = Path(repo_root) / "assets" / "courses" / "manifest.json"
    if not manifest.is_file():
        return codes
    try:
        data = json.loads(manifest.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise DeliveryError(f"无法读取 manifest.json：{exc}") from exc
    for item in data.get("languages") or []:
        if isinstance(item, dict) and item.get("code"):
            codes.add(str(item["code"]).strip())
    return codes


def find_manifest_entry(repo_root: Path, code: str) -> dict[str, Any] | None:
    manifest = Path(repo_root) / "assets" / "courses" / "manifest.json"
    if not manifest.is_file():
        return None
    try:
        data = json.loads(manifest.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    for item in data.get("languages") or []:
        if isinstance(item, dict) and str(item.get("code") or "") == code:
            return item
    return None


class _IdRewriter:
    def __init__(self, code: str) -> None:
        self.prefix = f"ll-{code}-"
        self.forward: dict[str, str] = {}
        self._owners: dict[str, str] = {}

    def assign(self, original: str) -> None:
        if original == "":
            return
        rewritten = original if original.startswith(self.prefix) else self.prefix + original
        previous = self.forward.get(original)
        if previous is not None:
            return
        owner = self._owners.get(rewritten)
        if owner is not None and owner != original:
            raise DeliveryError(
                f"id 冲突：{owner!r} 与 {original!r} 都会变成 {rewritten!r}"
            )
        self.forward[original] = rewritten
        self._owners[rewritten] = original


def _collect_ids(node: Any, rewriter: _IdRewriter) -> None:
    if isinstance(node, dict):
        for key, value in node.items():
            if (
                isinstance(value, str)
                and value
                and (key == "id" or key in REFERENCE_STRING_KEYS)
            ):
                rewriter.assign(value)
            elif key in REFERENCE_LIST_KEYS and isinstance(value, list):
                for item in value:
                    if isinstance(item, str) and item:
                        rewriter.assign(item)
            else:
                _collect_ids(value, rewriter)
    elif isinstance(node, list):
        for item in node:
            _collect_ids(item, rewriter)


def _apply_ids(node: Any, forward: dict[str, str]) -> None:
    if isinstance(node, dict):
        for key, value in list(node.items()):
            if (
                isinstance(value, str)
                and value in forward
                and (key == "id" or key in REFERENCE_STRING_KEYS)
            ):
                node[key] = forward[value]
            elif key in REFERENCE_LIST_KEYS and isinstance(value, list):
                node[key] = [
                    forward[item] if isinstance(item, str) and item in forward else item
                    for item in value
                ]
            elif key in MEDIA_STRING_KEYS and isinstance(value, str) and value in forward:
                # Bare word ids used as TTS audio follow the prefixed word.
                # ``media/…`` paths are not ids, so they stay put.
                node[key] = forward[value]
            elif key in MEDIA_LIST_KEYS and isinstance(value, list):
                node[key] = [
                    forward[item] if isinstance(item, str) and item in forward else item
                    for item in value
                ]
            else:
                _apply_ids(value, forward)
    elif isinstance(node, list):
        for item in node:
            _apply_ids(item, forward)


def rewrite_ids(node: Any, code: str) -> Any:
    """Return a deep copy whose course ids use ``ll-<code>-``.

    Already-prefixed ids stay as they are. Empty ids are left empty. Two
    different originals that land on one prefixed id raise :class:`DeliveryError`.
    File-path keys (``file``, ``sections/section1.json``) are not ids.
    """
    if not CODE_RE.fullmatch(code):
        raise DeliveryError(f"语言代码必须匹配 ^[a-z]{{2,3}}$（当前：{code!r}）")
    copied = deepcopy(node)
    rewriter = _IdRewriter(code)
    _collect_ids(copied, rewriter)
    _apply_ids(copied, rewriter.forward)
    return copied


def _read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise DeliveryError(f"无法读取 {path.name}：{exc}") from exc


def load_course_documents(course_dir: Path) -> dict[str, Any]:
    """Course JSON keyed by pack-relative path. Section file names stay put."""
    root = Path(course_dir)
    documents: dict[str, Any] = {}
    for name in ("index.json", "vocab.json", "expressions.json", "grammar_points.json"):
        path = root / name
        if path.is_file():
            documents[name] = _read_json(path)
    index = documents.get("index.json")
    if not isinstance(index, dict):
        raise DeliveryError("课程缺少 index.json")
    if "vocab.json" not in documents:
        raise DeliveryError("课程缺少 vocab.json")
    for entry in index.get("sections") or []:
        if not isinstance(entry, dict):
            continue
        rel = str(entry.get("file") or "").replace("\\", "/")
        if not rel or rel.startswith("/") or ".." in rel.split("/"):
            raise DeliveryError(f"章节文件路径无效：{rel!r}")
        path = root / rel
        if not path.is_file():
            raise DeliveryError(f"缺少章节文件 {rel}")
        documents[rel] = _read_json(path)
    return documents


def _unsafe_media_relative(relative: str) -> bool:
    parts = relative.split("/")
    return (
        not relative
        or relative.startswith("/")
        or any(part in {"", ".", ".."} for part in parts)
        or ":" in relative
        or relative.startswith("media/")
    )


def collect_media_refs(node: Any) -> set[str]:
    """``media/…`` refs from the known media fields. Other strings are ignored."""
    found: set[str] = set()

    def walk(value: Any) -> None:
        if isinstance(value, dict):
            for key, item in value.items():
                if key in MEDIA_STRING_KEYS and isinstance(item, str):
                    _add_media_ref(item, found)
                elif key in MEDIA_LIST_KEYS and isinstance(item, list):
                    for piece in item:
                        if isinstance(piece, str):
                            _add_media_ref(piece, found)
                else:
                    walk(item)
        elif isinstance(value, list):
            for item in value:
                walk(item)

    walk(node)
    return found


def _add_media_ref(raw: str, found: set[str]) -> None:
    text = raw.replace("\\", "/").strip()
    if not text.startswith("media/"):
        return
    relative = text[len("media/"):]
    if _unsafe_media_relative(relative):
        raise DeliveryError(f"媒体路径无效：{text}")
    suffix = Path(relative).suffix.lower()
    if suffix not in ALLOWED_MEDIA_EXTENSIONS:
        raise DeliveryError(f"媒体扩展名不支持：{text}")
    found.add(f"media/{relative}")


def _iter_media_files(course_dir: Path) -> list[Path]:
    media = Path(course_dir) / "media"
    if not media.is_dir():
        return []
    files: list[Path] = []
    for path in media.rglob("*"):
        if not path.is_file():
            continue
        rel_parts = path.relative_to(media).parts
        if any(part.startswith(".") for part in rel_parts):
            continue
        if path.suffix.lower() not in ALLOWED_MEDIA_EXTENSIONS:
            continue
        files.append(path)
    return files


def _pack_license(profile: LanguageProfile) -> tuple[dict[str, str], bool]:
    attribution = profile.license_attribution or profile.display_name
    if not profile.display_name:
        raise DeliveryError("导入要求 language.displayName 非空")
    if not profile.license_name or not attribution:
        raise DeliveryError("导入要求 license 的名称和署名都非空")
    substituted = not profile.license_attribution
    return (
        {
            "name": profile.license_name,
            "attribution": attribution,
            "link": profile.license_link,
        },
        substituted,
    )


def _pack_language(profile: LanguageProfile) -> dict[str, str]:
    language = {
        "code": profile.code,
        "displayName": profile.display_name,
        "ttsLocale": profile.tts_locale,
        "nativeLabel": profile.native_label,
    }
    if profile.signature_chars:
        language["signatureChars"] = profile.signature_chars
    return language


def build_pack_payload(
    course_dir: Path,
    *,
    repo_root: Path | None = None,
) -> tuple[dict[str, Any], dict[str, Path], bool]:
    """Return ``(pack json, zip media arc→file, attribution_was_filled)``.

    Raises when the language code is reserved or two ids collapse.
    """
    root = Path(course_dir)
    documents = load_course_documents(root)
    index = documents["index.json"]
    if not isinstance(index, dict):
        raise DeliveryError("index.json 必须是对象")
    profile = resolve_profile(index)
    reserved = builtin_codes(repo_root) if repo_root is not None else set(ALWAYS_RESERVED_CODES)
    if profile.code in reserved:
        raise DeliveryError(f"语言代码 {profile.code} 是内置课，不能导出为外部包")
    index_language = str(index.get("language") or "").strip()
    if index_language != profile.code:
        raise DeliveryError("index.language 与语言代码不一致")
    rewritten = rewrite_ids(documents, profile.code)
    refs = collect_media_refs(rewritten)
    on_disk = _iter_media_files(root)
    use_zip = bool(refs) or bool(on_disk)
    media_map: dict[str, Path] = {}
    for ref in sorted(refs):
        relative = ref[len("media/"):]
        path = root / "media" / relative
        if not path.is_file():
            raise DeliveryError(f"缺少媒体文件 {ref}")
        media_map[ref] = path
    for path in on_disk:
        arc = "media/" + path.relative_to(root / "media").as_posix()
        media_map.setdefault(arc, path)
    license_obj, substituted = _pack_license(profile)
    pack = {
        "format": "turnapack/2" if use_zip else "turnapack/1",
        "packVersion": 1,
        "language": _pack_language(profile),
        "license": license_obj,
        "files": rewritten,
    }
    return pack, media_map, substituted


def deliver_pack(course_dir: Path, out_path: Path, *, repo_root: Path | None = None) -> HandoffResult:
    """Write a ``.turnapack``. Does not modify the course directory."""
    pack, media_map, substituted = build_pack_payload(course_dir, repo_root=repo_root)
    destination = Path(out_path)
    if destination.suffix.lower() != ".turnapack":
        destination = destination.with_suffix(".turnapack")
    destination.parent.mkdir(parents=True, exist_ok=True)
    note = ""
    if substituted:
        note = "许可署名为空，包内已用课程显示名占位（App 导入要求署名非空）。"
    if pack["format"] == "turnapack/1":
        text = json.dumps(pack, ensure_ascii=False, indent=2) + "\n"
        encoded = text.encode("utf-8")
        if len(encoded) > 20 * 1024 * 1024:
            raise DeliveryError("v1 包超过 20 MB，请改用带媒体的 v2 或缩小课程")
        destination.write_bytes(encoded)
    else:
        with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            archive.writestr(
                "pack.json",
                json.dumps(pack, ensure_ascii=False, indent=2) + "\n",
            )
            for arc, src in sorted(media_map.items()):
                if not arc.startswith("media/") or ".." in arc.split("/"):
                    raise DeliveryError(f"媒体路径无效：{arc}")
                archive.write(src, arcname=arc)
        if destination.stat().st_size > 80 * 1024 * 1024:
            destination.unlink(missing_ok=True)
            raise DeliveryError("v2 包超过 80 MB")
    message = f"已写出 {destination}（{pack['format']}）。在 App 里导入该文件即可。"
    if note:
        message = f"{message}{note}"
    return HandoffResult(ok=True, message=message, output_path=str(destination))


def _dump_manifest(doc: dict[str, Any]) -> str:
    return json.dumps(doc, ensure_ascii=False, indent=2) + "\n"


def upsert_manifest_language(
    doc: dict[str, Any],
    profile: LanguageProfile,
    dir_name: str,
) -> dict[str, Any]:
    """Update descriptor fields of an existing code. Never change ``dir``.

    A new code is appended with ``dir`` equal to the course directory name.
    """
    languages = doc.setdefault("languages", [])
    if not isinstance(languages, list):
        raise DeliveryError("manifest.json 的 languages 必须是数组")
    for item in languages:
        if isinstance(item, dict) and str(item.get("code") or "") == profile.code:
            item["displayName"] = profile.display_name
            item["ttsLocale"] = profile.tts_locale
            if profile.native_label:
                item["nativeLabel"] = profile.native_label
            if profile.signature_chars:
                item["signatureChars"] = profile.signature_chars
            return doc
    entry: dict[str, Any] = {
        "code": profile.code,
        "displayName": profile.display_name,
        "ttsLocale": profile.tts_locale,
        "dir": dir_name,
        "nativeLabel": profile.native_label,
    }
    if profile.signature_chars:
        entry["signatureChars"] = profile.signature_chars
    languages.append(entry)
    return doc


def insert_course_asset_lines(text: str, dir_name: str) -> str:
    """Idempotently ensure the three Flutter asset lines for ``dir_name``."""
    if not dir_name or "/" in dir_name or "\\" in dir_name or dir_name.startswith("."):
        raise DeliveryError(f"课程目录名无效：{dir_name!r}")
    wanted = [
        f"assets/courses/{dir_name}/",
        f"assets/courses/{dir_name}/sections/",
        f"assets/courses/{dir_name}/media/",
    ]
    newline = "\r\n" if "\r\n" in text else "\n"
    lines = text.splitlines()
    stripped = [line.strip() for line in lines]
    wanted_stripped = {f"- {item}" for item in wanted}
    if wanted_stripped <= set(stripped):
        return text if text.endswith(("\n", "\r\n")) or text == "" else text + newline
    indent = "    "
    for line in lines:
        if line.strip().startswith("- assets/"):
            indent = line[: len(line) - len(line.lstrip(" \t"))]
            break
    existing_at = [i for i, item in enumerate(stripped) if item in wanted_stripped]
    if existing_at:
        anchor = existing_at[0]
        for index in reversed(existing_at):
            del lines[index]
            if index < anchor:
                anchor -= 1
    else:
        anchor = None
        for i, item in enumerate(stripped):
            if item.startswith("- assets/courses/"):
                anchor = i + 1
        if anchor is None:
            for i, item in enumerate(stripped):
                if item == "assets:":
                    anchor = i + 1
                    break
        if anchor is None:
            raise DeliveryError("pubspec.yaml 里找不到 flutter assets 列表")
    block = [f"{indent}- {item}" for item in wanted]
    lines[anchor:anchor] = block
    body = newline.join(lines)
    if text.endswith(("\n", "\r\n")) or text == "":
        body += newline
    return body


def _ensure_media_dir(course_dir: Path) -> None:
    media = Path(course_dir) / "media"
    if media.is_dir() and any(media.iterdir()):
        return
    media.mkdir(parents=True, exist_ok=True)
    keep = media / ".gitkeep"
    if not any(path for path in media.iterdir() if path.name != ".gitkeep"):
        keep.write_text("", encoding="utf-8")


def deliver_builtin(course_dir: Path, repo_root: Path) -> HandoffResult:
    """Upsert the manifest row and the three pubspec asset lines."""
    root = Path(repo_root)
    course = Path(course_dir)
    dir_name = repo_course_dir_name(course, root)
    if dir_name is None:
        raise DeliveryError("这门课不在仓库的 assets/courses/<目录>/ 里，不能登记为内置课")
    documents = load_course_documents(course)
    index = documents["index.json"]
    if not isinstance(index, dict):
        raise DeliveryError("index.json 必须是对象")
    code = str(index.get("language") or "").strip()
    entry = find_manifest_entry(root, code)
    profile = resolve_profile(index, manifest_entry=entry)
    manifest_path = root / "assets" / "courses" / "manifest.json"
    if manifest_path.is_file():
        doc = _read_json(manifest_path)
        if not isinstance(doc, dict):
            raise DeliveryError("manifest.json 必须是对象")
    else:
        doc = {"languages": []}
    before = deepcopy(doc)
    upsert_manifest_language(doc, profile, dir_name)
    if doc != before:
        manifest_path.parent.mkdir(parents=True, exist_ok=True)
        manifest_path.write_text(_dump_manifest(doc), encoding="utf-8")
    pubspec_path = root / "pubspec.yaml"
    if not pubspec_path.is_file():
        raise DeliveryError("仓库里找不到 pubspec.yaml")
    original = pubspec_path.read_text(encoding="utf-8")
    updated = insert_course_asset_lines(original, dir_name)
    if updated != original:
        _ensure_media_dir(course)
        pubspec_path.write_text(updated, encoding="utf-8")
    return HandoffResult(
        ok=True,
        message=(
            f"已登记语言 {profile.code}（目录 {dir_name}）。"
            "请重新构建 App 后，这门课才会出现在安装包里。"
        ),
    )
